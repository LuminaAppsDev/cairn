#!/usr/bin/env python3
"""Assert that Gradle's dependency verification is actually in force.

Gradle's checksum enforcement proves the pinned hashes match the bytes a
repository served. It cannot prove two further things this project relies on:

1. That verification is switched on at all. One
   ``org.gradle.dependency.verification=off`` line in a *tracked*
   ``gradle.properties`` disables the whole mechanism while builds still
   print BUILD SUCCESSFUL and the pin file still looks pristine. Verified
   against this repo: with that line present, a deliberately corrupted pin
   builds an APK and exits 0.
2. That the pin file still says what a human agreed to. Gradle is equally
   happy to "verify" a file whose policy was relaxed or whose entries were
   deleted.

Every check is stateless -- it reads only the working tree -- except the
optional ``--base`` comparison, which is fail-closed: if a base revision is
named but cannot be read, this errors rather than passing quietly. A check
that silently degrades to "nothing to compare" is worse than no check,
because it still prints an all-clear.

Exit status: 0 clean, 1 findings, 2 the check could not run.
"""

from __future__ import annotations

import argparse
import subprocess  # nosec B404 - read-only `git` calls, fixed argv, no shell
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Iterable, NamedTuple

# Resolved from this file, not the cwd, so the check behaves identically
# from a CI step, a git hook, or an interactive shell.
REPO_ROOT = Path(__file__).resolve().parent.parent
METADATA = Path("android/gradle/verification-metadata.xml")
WRAPPER = Path("android/gradle/wrapper/gradle-wrapper.properties")

# The property that turns verification off or down. `lenient` still reports
# failures but does not fail the build, so it is no better than `off` here.
# Only `strict` is acceptable, and `strict` is the default.
MODE_PROPERTY = "org.gradle.dependency.verification"

# Elements granting blanket trust. Each means "skip verification for
# whatever this matches", shrinking coverage while the file still parses
# and every build still succeeds.
TRUST_ESCAPES = (
    "trusted-artifacts",
    "trusted-key",
    "trusted-keys",
    "trusting",
    "ignored-keys",
)

# Directories holding build output rather than tracked configuration.
SKIP_DIRS = {"build", ".gradle", ".dart_tool"}


class Finding(NamedTuple):
    """One reason to fail, with enough context to act on it."""

    check: str
    message: str


class ArtifactKey(NamedTuple):
    """Identity of a pinned artifact: coordinate plus file name."""

    group: str
    name: str
    version: str
    artifact: str


Pins = dict[ArtifactKey, set[str]]


def local_name(tag: str) -> str:
    """Strip the XML namespace, leaving the local element name."""
    return tag.rsplit("}", 1)[-1]


def parse_xml(text: str) -> ET.Element | None:
    """Parse the metadata, returning None when it is malformed."""
    try:
        # nosec B314 - local, repo-controlled file
        return ET.fromstring(text)  # noqa: S314
    except ET.ParseError:
        return None


def iter_named(root: ET.Element, wanted: str) -> Iterable[ET.Element]:
    """Yield every element whose local name matches, any namespace."""
    for element in root.iter():
        if local_name(element.tag) == wanted:
            yield element


def artifact_checksums(artifact: ET.Element) -> set[str]:
    """Collect every checksum accepted for one artifact.

    Gradle carries the digest in a ``value`` *attribute*, not element text
    -- ``<sha256 value="ab12..." origin="..."/>`` -- and allows further
    accepted digests as nested ``<also-trust value="..."/>``. Reading
    ``.text`` yields the empty string for every artifact, which compares
    equal everywhere and turns the drift comparison into a no-op that still
    prints an all-clear. This function exists because the first version of
    this script did exactly that.
    """
    checksums: set[str] = set()
    for child in artifact:
        if local_name(child.tag) != "sha256":
            continue
        value = (child.get("value") or "").strip()
        if value:
            checksums.add(value)
        for nested in child:
            if local_name(nested.tag) == "also-trust":
                trusted = (nested.get("value") or "").strip()
                if trusted:
                    checksums.add(trusted)
    return checksums


def parse_pins(text: str, source: str) -> tuple[Pins, list[Finding]]:
    """Map each pinned artifact to its checksums, reporting faults.

    Checksums go into a *set* rather than being assigned, mirroring
    Gradle's own merge semantics for duplicate ``<artifact>`` entries.
    Assigning would let a second entry overwrite the first, hiding a
    duplicate Gradle would have merged.
    """
    root = parse_xml(text)
    if root is None:
        return {}, [Finding("parse", f"{source} is not well-formed XML")]

    findings: list[Finding] = []
    pins: Pins = {}
    for component in iter_named(root, "component"):
        group = component.get("group", "")
        name = component.get("name", "")
        version = component.get("version", "")
        coord = f"{group}:{name}:{version}"
        seen: set[str] = set()
        for artifact in component:
            if local_name(artifact.tag) != "artifact":
                continue
            filename = artifact.get("name", "")
            if filename in seen:
                findings.append(
                    Finding(
                        "duplicate-artifact",
                        f"{source}: {coord} lists '{filename}' twice; "
                        "Gradle merges duplicates, so one is invisible",
                    )
                )
            seen.add(filename)
            checksums = artifact_checksums(artifact)
            if not checksums:
                findings.append(
                    Finding(
                        "missing-checksum",
                        f"{source}: {coord} artifact '{filename}' has no "
                        "sha256, so it is not verified at all",
                    )
                )
            key = ArtifactKey(group, name, version, filename)
            pins.setdefault(key, set()).update(checksums)
    return pins, findings


def check_policy(text: str) -> list[Finding]:
    """Fail if the metadata's own settings weaken verification."""
    root = parse_xml(text)
    if root is None:
        return []  # parse_pins already reported this.

    findings: list[Finding] = []
    flags = list(iter_named(root, "verify-metadata"))
    if not flags:
        findings.append(Finding("policy", "<verify-metadata> is absent"))
    for element in flags:
        if (element.text or "").strip().lower() != "true":
            findings.append(
                Finding(
                    "policy",
                    "<verify-metadata> is not true",
                )
            )
    for element in root.iter():
        tag = local_name(element.tag)
        if tag in TRUST_ESCAPES:
            findings.append(
                Finding(
                    "policy",
                    f"<{tag}> grants blanket trust and shrinks coverage "
                    "silently; remove it or justify it explicitly",
                )
            )
    return findings


def check_verification_enabled(root_dir: Path) -> list[Finding]:
    """Fail if any gradle.properties turns verification off or down.

    This is the check the script exists for. The property is honoured from
    any gradle.properties Gradle reads, including the tracked one under
    android/, and it defeats every pinned checksum without touching the
    pin file at all.
    """
    findings: list[Finding] = []
    for path in sorted(root_dir.glob("**/gradle.properties")):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        relative = path.relative_to(root_dir)
        lines = path.read_text().splitlines()
        for number, line in enumerate(lines, start=1):
            stripped = line.strip()
            if stripped.startswith("#") or "=" not in stripped:
                continue
            key, _, value = stripped.partition("=")
            key = key.strip()
            if key.removeprefix("systemProp.") != MODE_PROPERTY:
                continue
            if value.strip() != "strict":
                findings.append(
                    Finding(
                        "verification-disabled",
                        f"{relative}:{number} sets {key}="
                        f"{value.strip()}; this disables checksum "
                        "verification while builds still succeed",
                    )
                )
    return findings


def check_wrapper_pinned(root_dir: Path) -> list[Finding]:
    """Fail if the Gradle distribution itself is unpinned.

    That distribution is what interprets the metadata. Unpinned, it is
    fetched on TLS alone, and a substituted distribution would not have to
    defeat checksum pinning -- it could decline to honour it.
    """
    path = root_dir / WRAPPER
    if not path.is_file():
        return [Finding("wrapper", f"{WRAPPER} is missing")]
    for line in path.read_text().splitlines():
        if line.strip().startswith("distributionSha256Sum="):
            return []
    return [
        Finding(
            "wrapper",
            f"{WRAPPER} has no distributionSha256Sum: the Gradle "
            "distribution enforcing the pins is itself unverified",
        )
    ]


def git_show(revision: str, path: Path, root_dir: Path) -> str | None:
    """Return a file's contents at a revision, or None if absent there.

    Raises RuntimeError when the revision cannot be resolved. A missing
    file at a valid revision is ordinary -- it was added later -- but an
    unresolvable revision means the comparison never ran, and that must
    not pass.
    """
    # Reject flag-shaped revisions rather than passing them through. git has
    # no end-of-options separator that works here: `rev-parse --verify --`
    # is refused outright, and `git show -- <rev>:<path>` treats the argument
    # as a pathspec and returns nothing while still exiting 0 -- which would
    # make the base look empty and pass every comparison silently.
    if revision.startswith("-"):
        raise RuntimeError(f"refusing flag-shaped revision '{revision}'")
    git = ["git", "-C", str(root_dir)]
    probe = subprocess.run(  # nosec B603 - fixed argv, no shell
        git + ["rev-parse", "--verify", f"{revision}^{{commit}}"],
        capture_output=True,
        text=True,
        check=False,
    )
    if probe.returncode != 0:
        raise RuntimeError(f"cannot resolve base revision '{revision}'")
    show = subprocess.run(  # nosec B603 - fixed argv, no shell
        git + ["show", f"{revision}:{path.as_posix()}"],
        capture_output=True,
        text=True,
        check=False,
    )
    return show.stdout if show.returncode == 0 else None


def check_drift(old: Pins, new: Pins) -> list[Finding]:
    """Fail on changes a legitimate version bump cannot explain.

    Published Maven artifacts are immutable, so a checksum that moved
    under an unchanged coordinate is never routine. A removal is routine
    only when the same group:name reappears at another version; an
    unpaired removal is a pin being dropped, which is how coverage shrinks
    unnoticed.
    """
    findings: list[Finding] = []
    for key, checksums in sorted(new.items()):
        previous = old.get(key)
        if previous is not None and previous != checksums:
            findings.append(
                Finding(
                    "checksum-drift",
                    f"{key.group}:{key.name}:{key.version} artifact "
                    f"'{key.artifact}' changed checksum with no version "
                    "change; published artifacts are immutable, so "
                    "explain this before committing",
                )
            )
    added = {(k.group, k.name) for k in new if k not in old}
    for key in sorted(set(old) - set(new)):
        if (key.group, key.name) not in added:
            findings.append(
                Finding(
                    "pin-removed",
                    f"{key.group}:{key.name}:{key.version} artifact "
                    f"'{key.artifact}' was removed with no replacement "
                    "version added; coverage shrank rather than moved",
                )
            )
    return findings


def build_parser() -> argparse.ArgumentParser:
    """Construct the command-line parser."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--base",
        metavar="REV",
        help="git revision to compare pins against; fails if unresolvable",
    )
    parser.add_argument(
        "--min-artifacts",
        type=int,
        default=1000,
        help="fail below this many pinned artifacts (default: %(default)s)",
    )
    return parser


def compare_with_base(base: str, pins: Pins) -> tuple[list[Finding], bool]:
    """Compare against a base revision. Returns (findings, could_run)."""
    try:
        old_text = git_show(base, METADATA, REPO_ROOT)
    except RuntimeError as exc:
        print(f"error: {exc}; refusing to pass", file=sys.stderr)
        return [], False
    if old_text is None:
        print(f"note: {METADATA} absent at {base}; drift check skipped")
        return [], True
    old_pins, old_findings = parse_pins(old_text, f"{METADATA}@{base}")
    if old_findings:
        print(f"note: base {base} has its own faults; comparing anyway")
    return check_drift(old_pins, pins), True


def main() -> int:
    """Run every check. See the module docstring for exit codes."""
    args = build_parser().parse_args()
    path = REPO_ROOT / METADATA
    if not path.is_file():
        print(f"error: {METADATA} not found", file=sys.stderr)
        return 2

    text = path.read_text()
    pins, findings = parse_pins(text, METADATA.as_posix())
    findings += check_policy(text)
    findings += check_verification_enabled(REPO_ROOT)
    findings += check_wrapper_pinned(REPO_ROOT)
    if len(pins) < args.min_artifacts:
        findings.append(
            Finding(
                "coverage",
                f"only {len(pins)} artifacts pinned, expected at least "
                f"{args.min_artifacts}; coverage has shrunk",
            )
        )

    if args.base:
        drift, could_run = compare_with_base(args.base, pins)
        if not could_run:
            return 2
        findings += drift

    if findings:
        print(f"FAIL: {len(findings)} finding(s)", file=sys.stderr)
        for finding in findings:
            print(f"  [{finding.check}] {finding.message}", file=sys.stderr)
        return 1

    print(f"OK: {len(pins)} artifacts pinned, verification enforced")
    return 0


if __name__ == "__main__":
    sys.exit(main())
