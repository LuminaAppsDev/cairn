# Cairn — Release Guide

How to ship Cairn on each distribution channel. This complements
[`DEVELOPMENT.md`](DEVELOPMENT.md) (dev setup, signing config, toolchains) and
the distribution decision in [`DESIGN.md` §10.3](DESIGN.md). It does **not**
repeat the signing/keystore setup — see DEVELOPMENT.md §3.3 (Android) and §3.4
(iOS).

> **Store requirements drift.** Apple/Google/F-Droid/Nextcloud change policies
> and version requirements regularly. Treat the version numbers and form names
> here as a starting point and confirm against the linked official docs before
> each release.

---

## 0. What ships

Cairn has **two independently-released artifacts**:

| Artifact | Stack | Licence | Channels | Status |
| --- | --- | --- | --- | --- |
| **Mobile app** | Flutter (Android + iOS), `com.luminaapps.cairn` | MIT | F-Droid, sideload, Google Play, Apple App Store | shipping (Phases 1–5) |
| **Nextcloud web app** | classic Nextcloud app (PHP + Vue) | AGPL-3.0 | Nextcloud App Store | **not built yet — Phase 7**; §6 is forward-looking |

**Distribution philosophy (DESIGN.md §10.3):** the strict, no-compromise build
ships cleanest via **F-Droid / sideload** (plus a personal/community iOS build),
which also sidesteps most of the Google Play health-policy friction. Google Play
and the Apple App Store are possible but need careful store-listing and
data-use scoping. Decide per channel. Cairn is **not** a medical device — never
use diagnostic/treatment framing in any listing.

**Store name:** the listing title is **Cairn: Health Aggregator** (set in
`fastlane/metadata/android/` and, for Apple, in App Store Connect), used
consistently across F-Droid, Google Play and the App Store. The on-device
launcher label stays the short **Cairn** (`android:label` / iOS
`CFBundleDisplayName`).

---

## 1. Common pre-release checklist

Do this once per release, before touching any channel:

- [ ] **Quality gate green** (DESIGN.md §13): `dart format --output=none
      --set-exit-if-changed .`, `dart analyze`, `flutter test`, and the binding
      `/review` + `/security-audit`.
- [ ] **Bump the version** in [`pubspec.yaml`](../pubspec.yaml):
      `version: X.Y.Z+BUILD`. `X.Y.Z` is the user-facing `versionName`; `BUILD`
      is the integer `versionCode` (Android) / build number (iOS) — **it must
      increase on every store upload**, even a re-upload of the same `X.Y.Z`.
- [ ] **Update [`CHANGELOG.md`](../CHANGELOG.md)** and tag the commit
      (`vX.Y.Z`).
- [ ] **Permission/data-use audit** — confirm the app still requests only what
      it uses (READ-only health types; no `WRITE_*`; see DESIGN.md §2). If the
      health types changed, the store declarations (Play/Apple) must be updated.
- [ ] **Privacy policy** published on a **public, non-geofenced HTTPS URL**
      (required by Apple and Google; good practice everywhere). It must state:
      what health data is read, that it is stored only in the user's own
      Nextcloud, that Cairn (the project) stores nothing, no advertising/no
      data-mining, and how to delete data (delete the `/Cairn/` folder /
      disconnect). Keep the source as `docs/PRIVACY.md` → publish it.
- [ ] **Secrets check** — the release keystore + `key.properties` are present
      locally and **never** committed (gitignored + `.githooks/pre-commit`).
      Back up the keystore securely; losing it means you can never update the
      app under the same identity.
- [ ] **Smoke-test the signed release build on a device** — `flutter run
      --release` (or install the built APK) and confirm it launches and the core
      screens load. CI builds + tests the APK but never launches it, so a
      release-only failure (e.g. an R8 strip of a reflectively-loaded class)
      won't surface in CI.

---

## 2. F-Droid (primary channel)

F-Droid is the cleanest home for Cairn: it's a FOSS-only repository, and Cairn
is MIT, ships **no** Google Play Services / Firebase / proprietary blobs, does
no tracking, and talks only to the **user's own** Nextcloud (so it should not
attract the `NonFreeNet` / `Tracking` anti-features). Reading Health Connect is
an on-device API call, not a proprietary dependency bundled in the APK.

There are two routes. The **official repo** gives discoverability; a
**self-hosted repo** gives full control and a faster cadence. You can do both.

### 2a. Official F-Droid repository

F-Droid **builds your app from source** on their infrastructure and signs it
with the F-Droid key (or verifies a reproducible build against your own
signature). Requirements: an OSI-approved licence (MIT ✓), a tagged source
release, and no proprietary dependencies or anti-features.

Flutter is supported. The build recipe pulls the Flutter SDK via either a
`srclibs: - flutter@stable` entry or Flutter vendored as a git submodule; see
the official **`build-flutter.yml`** template. A typical recipe:

- `sudo`/`prebuild` to fetch + pin the Flutter SDK version,
- remove non-Android platform dirs (`ios`, `linux`, `macos`, `web`, `windows`),
- `build: flutter build apk` (or per-ABI),
- `output:` pointing at the built APK.

Steps:

1. Read **Submitting to F-Droid (Quick Start)** and the **Inclusion Policy**.
2. Make sure each release is a **git tag** with a bumped `versionCode`.
3. Open an **RFP (Request For Packaging)** issue, then a merge request adding a
   metadata file to the **`fdroiddata`** repo (`metadata/com.luminaapps.cairn.yml`):
   licence, source/repo URLs, `Build:` block (the Flutter recipe above),
   `AutoUpdateMode`/`UpdateCheckMode: Tags`, and `CurrentVersion`/`CurrentVersionCode`.
4. F-Droid CI builds it; iterate on the MR until it builds clean; on merge it's
   published and auto-tracks new tags.
5. **Reproducible builds — enabled.** Cairn ships *its own* signature on
   F-Droid: F-Droid rebuilds each tag and compares the result byte-for-byte
   against the per-ABI APKs this repo publishes, then distributes our APK
   instead of an F-Droid-signed one. Sideload and F-Droid installs are therefore
   interchangeable. See §2a-repro below for what this requires — it is *not*
   optional once enabled, because a verification failure means the build fails
   and **nothing is published** for that version. Reproducible builds are not an
   F-Droid entry requirement, but the choice is one-way: Android refuses
   in-place upgrades across a signature change, so it cannot be turned on later
   without every user reinstalling.

**In this repo:** a ready-to-submit recipe lives at
[`fdroid/com.luminaapps.cairn.yml`](../fdroid/com.luminaapps.cairn.yml)
— copy it into your `fdroiddata` fork as
`metadata/com.luminaapps.cairn.yml` for the merge request. The listing
text, changelogs and feature graphic are auto-imported by F-Droid from
[`fastlane/metadata/android/`](../fastlane/metadata/android/), so they live with
the app, not in the recipe — **add your phone screenshots** under each locale's
`images/phoneScreenshots/` (layout + specs in
[`fastlane/metadata/README.md`](../fastlane/metadata/README.md)). The recipe pins Flutter to the version it reads out
of `.forgejo/workflows/release.yml`, so CI and the F-Droid build stay in lockstep.

### 2a-repro. What reproducible builds require

Both sides — this repo's release CI and F-Droid's buildserver — must compile at
the **same absolute path**, because Dart's AOT compiler embeds the Flutter
project root into `libapp.so` (flutter/flutter#165111): a release APK literally
contains `file://<project root>/.dart_tool/flutter_build/dart_plugin_registrant.dart`.

| Piece | Where | What it does |
| --- | --- | --- |
| `BUILD_DIR: /build/cairn` | [`.forgejo/workflows/release.yml`](../.forgejo/workflows/release.yml) | Stages the checkout there; every Flutter/Gradle step compiles from it |
| `sudo: mkdir -p /build` + `mv`/`pushd` | [`fdroid/com.luminaapps.cairn.yml`](../fdroid/com.luminaapps.cairn.yml) | Moves F-Droid's checkout onto the same path, in **both** `prebuild` and `build` |
| `-Wl,--build-id=none` | [`android/build.gradle.kts`](../android/build.gradle.kts) | Drops the GNU build-id from natively-compiled plugin libraries (see below) |
| `dependenciesInfo { includeInApk = false }` | [`android/app/build.gradle.kts`](../android/app/build.gradle.kts) | Stops AGP embedding a Play-encrypted payload F-Droid rejects (see below) |
| per-block `binary:` + `AllowedAPKSigningKeys:` | the fdroiddata recipe | Tells F-Droid which APK each block verifies against, and which signing key to expect |

**One-time host prep on the release runner.** Do this once, as root, before the
first reproducible release. The release job itself **never calls sudo** — it
only verifies `/build` and fails closed with these instructions if the check
does not pass. That is deliberate: a passwordless sudo grant reachable from the
job would also be reachable by every dependency the build resolves, which is a
much larger exposure than the signing key it would be guarding.

```bash
sudo mkdir -p /build
sudo chown "$(id -u -n <runner-user>):" /build
sudo chmod 700 /build
```

The job checks that `/build` exists, is not a symlink, is owned by the runner
uid, is mode `700`, and has at least 8 GiB free.

**Residual risk worth a compensating control.** The decoded keystore and
`key.properties` live inside `/build/cairn` for the duration of a release. The
`if: always()` cleanup removes them on success, failure and cancellation — but
not if the runner process or host is hard-killed, in which case they persist
until the next release run wipes the staging tree. On a host whose disk is not
discarded between jobs, consider backing `/build` with `tmpfs`, or adding a
`systemd-tmpfiles` rule to reap it on boot and by age.

**Why `--build-id=none`.** The Android NDK sits at `/opt/android-sdk/ndk/…` on
F-Droid's buildserver and somewhere under the runner's home here. That path
lands in the debug info of `package:jni`'s `libdartjni.so`; the linker hashes the
*unstripped* object into a GNU build-id note, and stripping then discards the
debug info but leaves the differing hash. Two byte-identical libraries end up
differing by exactly those 20 bytes. The flag lives in `build.gradle.kts` rather
than an environment variable so CI and F-Droid cannot drift apart.

What it costs: the build-id is the identifier crash-symbolication tools use to
match a stripped `.so` back to its symbols. Cairn ships no native crash
reporter, so nothing consumes it today — but if one is ever added, archive the
unstripped `.so` per release tag and ABI, because the build-id mapping is gone.

The flag is injected through `com.android.build.api.dsl.LibraryExtension`, not
the legacy `com.android.build.gradle` class of the same name: AGP 9 deprecates
that one ("will be removed in AGP 10.0") and does not register it as the public
extension when `android.newDsl=true`, which is AGP 9's own default. Verified in
an isolated project that the legacy lookup fails outright under `newDsl=true`
(`Extension of type 'LibraryExtension' does not exist`) while the modern one
resolves under both settings. Scope limit worth knowing: the full native
rebuild could only be verified with `newDsl=false`, because Flutter's own Gradle
plugin fails to apply under `newDsl=true` — which is also why the template pins
it off. Both DSL views wrap one backing object, so the risk is low, but revisit
this when Flutter supports the new DSL.

**Why `dependenciesInfo` is off.** AGP embeds a dependency-metadata payload —
roughly 5 KB, encrypted for Google Play — into the APK *signing* block by
default. A FOSS repo cannot inspect it, so F-Droid's scanner rejects any APK
carrying it: *"Found extra signing block 'Dependency metadata'"*. This is checked
against the **reference binary**, i.e. the APK published here, so it fails the
whole verification regardless of how the rebuild went.

It is easy to miss, because the block sits between the zip entries and the
central directory: comparing two APKs entry by entry reports them as identical
while both carry it. That is exactly how it survived into v0.2.2. Any local
comparison must inspect the signing-block ID list as well — expect only a v2
signature and padding.

**Verifying locally before you tag.** `fdroid verify` is no help — it hardcodes
the f-droid.org repo URL and only works for already-published apps. Instead,
build in F-Droid's own image and compare:

```bash
podman pull registry.gitlab.com/fdroid/fdroidserver:buildserver
# build the tag at /build/cairn inside the image, then diff the APK entries
# against the one CI produces. Signature entries (META-INF/*.SF|RSA|EC,
# MANIFEST.MF) are excluded: F-Droid rebuilds unsigned and copies our signature
# across with apksigcopier, so only the zip *content* has to match.
```

Gotchas that will waste your afternoon: Gradle's build cache and AGP's CMake
cache (inside `PUB_CACHE`, at `…/jni-1.0.0/android/.cxx`) both serve stale
output and make a failed change look like a working one — clear both when
testing. `LDFLAGS` does **not** reach AGP's CMake invocation. Never run two
buildserver containers against one shared SDK volume.

**The recipe is kept in canonical `rewritemeta` form, and carries no comments.**
fdroiddata's CI runs `fdroid rewritemeta` and fails the merge request on any
diff, so the submitted file must already match byte for byte what that tool
emits — field order, line folding, blank lines between build blocks, trailing
newline. `rewritemeta` also strips every comment, so a documented copy cannot
survive the round trip. That is why the explanation lives in this document and
[`fdroid/com.luminaapps.cairn.yml`](../fdroid/com.luminaapps.cairn.yml) is pure
data: the file in this repo and the file in the merge request are then the same
file, with no regeneration step to forget. See §2a-recipe for what each field
means.

**Regenerating it requires matching CI's toolchain, not just running the local
`fdroid`.** The canonical form depends on the *ruamel.yaml* version doing the
emitting, not on fdroidserver. Debian trixie — which fdroiddata's CI runs — ships
ruamel 0.18.10, whose emitter folds a plain scalar longer than the line width
onto the following line:

```yaml
    binary: 
      https://github.com/LuminaAppsDev/cairn/releases/download/v%v/cairn-v%v-x86_64.apk
```

ruamel 0.17.x does not fold it at any width. A file canonicalised against 0.17.x
therefore fails CI with a confusing whitespace-only diff, even though both
fdroidserver 2.4.5 and current master agree on everything else. CI also fetches
fdroidserver from git master rather than using the Debian package. To reproduce
both:

```bash
# mktemp, not a fixed /tmp path: on a shared host a predictable name can be
# pre-created as a symlink before the tarball is extracted into it.
work=$(mktemp -d)

# fdroidserver master, as CI does
mkdir -p "$work/fdroidserver"
curl -fsS https://gitlab.com/fdroid/fdroidserver/-/archive/master/fdroidserver-master.tar.gz \
  | tar -xz --directory="$work/fdroidserver" --strip-components=1
# ruamel matching Debian trixie
python3 -m venv --system-site-packages "$work/venv"
"$work/venv/bin/pip" install 'ruamel.yaml==0.18.10'

cp fdroid/com.luminaapps.cairn.yml <fdroiddata>/metadata/
cd <fdroiddata> || exit
PYTHONPATH="$work/fdroidserver" "$work/venv/bin/python" \
  "$work/fdroidserver/fdroid" rewritemeta com.luminaapps.cairn
```

Run it twice and confirm the second run changes nothing; then copy the result
back over the repo copy so the two never diverge.

**Order of operations when cutting a reproducible release.** The recipe pins an
immutable `commit:`, which cannot be known until the release commit exists — so
the recipe is always updated *after* the tag, never in the same commit. Doing it
in one step produces a recipe that claims a version it is not pinned to, and
F-Droid would then rebuild the previous source and fail the byte comparison (or,
before reproducibility is enforced, publish the old packaging under the new
version number).

1. Commit the app, CI, changelog and docs changes — **leave the recipe alone**.
2. Tag `vX.Y.Z` and let CI publish the four assets.
3. In a follow-up commit, update the recipe: `commit:` in every build block to
   the tagged SHA, `versionName`/`versionCode`, the `binary:` URLs, and
   `CurrentVersion`/`CurrentVersionCode`. The recipe carries no comments, so
   there is nothing there to go stale — but §2a-recipe below *does* quote version
   codes in prose, so grep this document for the old numbers too.
4. Regenerate the canonical form with the toolchain above, confirm a second run
   changes nothing, and copy the result back over the repo copy so the two never
   diverge.

**Key custody — read this before losing the keystore.** Enabling reproducible
builds moves the signing key onto the critical path for *distribution*, not just
for uploads. `AllowedAPKSigningKeys` pins exactly one certificate, and
`AutoUpdateMode: Version` means every future tag is picked up and gated on it
without another human-reviewed metadata change.

- **Key lost.** F-Droid permanently stops shipping updates to existing installs
  the moment a tag is cut with a different keystore: the rebuilt APK's signer no
  longer matches the pin, so the build fails and nothing publishes. Android also
  refuses an in-place upgrade across a signature change, so there is no fix on
  the F-Droid side — only a new listing under a different application id, which
  every user must install manually. Keep the offline backup current and verify
  it restores.
- **Key compromised.** An attacker holding the private key can produce an APK
  that *passes* the pin. The only remaining protection is the byte-for-byte
  rebuild from the pinned `commit:`, which holds only as long as they cannot also
  land a matching commit. Treat a keystore compromise as requiring a new
  application id, a user-facing advisory, and an fdroiddata metadata change —
  not a key rotation.
- **Deliberate rotation** has the same cost as loss. There is no supported
  transition path; plan on it never happening.

Because of that asymmetry, the keystore backup is a release-blocking
prerequisite here, not general good practice.

**Residual risk.** R8 and baseline-profile generation are documented as
sensitive to CPU core count, which differs between the runner and F-Droid's
builder. That cannot be reproduced locally; it only shows up on F-Droid's CI.

Sources: [Submitting Quick Start](https://f-droid.org/en/docs/Submitting_to_F-Droid_Quick_Start_Guide/),
[Build Metadata Reference](https://f-droid.org/en/docs/Build_Metadata_Reference/),
[`build-flutter.yml` template](https://gitlab.com/fdroid/fdroiddata/-/blob/master/templates/build-flutter.yml),
[Reproducible Builds](https://f-droid.org/en/docs/Reproducible_Builds/).

### 2a-deps. Dependency verification

[`android/gradle/verification-metadata.xml`](../android/gradle/verification-metadata.xml)
pins a SHA-256 for every Maven artifact the Android build resolves — around 900
components, covering the app's own dependencies *and* the buildscript classpath
(AGP, the Kotlin plugin, Flutter's engine artifacts). Gradle refuses to build if
an artifact's checksum does not match, or if it resolves an artifact the file
does not list at all. Both F-Droid and this repo's CI enforce it, because the
file lives in the repo — and so does every contributor's machine, the moment it
touches Gradle. There is no way to enable it on one side only.

The trust anchor underneath it is
[`android/gradle/wrapper/gradle-wrapper.properties`](../android/gradle/wrapper/gradle-wrapper.properties),
which pins `distributionSha256Sum` for the Gradle distribution. Without that,
the distribution that *interprets* the verification metadata is itself fetched
on nothing but TLS — a substituted distribution would not have to defeat
checksum pinning, it could simply decline to honour it. Confirmed the pin
enforces: with a deliberately wrong sum the wrapper refuses to run
(*"Verification of Gradle distribution failed!"*). When bumping Gradle, take the
new sum from `https://services.gradle.org/distributions/<dist>.sha256`.

Note what is and is not tracked here. `gradlew`, `gradlew.bat` and
`gradle-wrapper.jar` are gitignored by Flutter's template and have never been
committed; the Flutter tool recreates them from its own cached
`gradle_wrapper` artifact when they are missing. Committing them is **not** the
fix it looks like: fdroidserver's scanner names those three files explicitly and
deletes them from the source tree before building, so a committed copy is not
what would run. What *is* tracked is `gradle-wrapper.properties` — so the
distribution pin survives regeneration even though the binary enforcing it is
supplied by the pinned Flutter SDK rather than by this repo. That leaves the
wrapper binary inside Flutter's supply chain rather than ours, which is the same
trust boundary the SDK itself sits on.

This is what makes the dependency set tamper-evident, and it is why the repo
does **not** set `repositoriesMode`. The obvious hardening —
`RepositoriesMode.FAIL_ON_PROJECT_REPOS` in `settings.gradle.kts`, so that only
settings-declared repositories are consulted — is not available to a Flutter
app:

- Every Flutter plugin's `android/build.gradle` declares
  `rootProject.allprojects { repositories { … } }`, and **Flutter's own Gradle
  plugin does the same** to add the engine repository. The strict mode therefore
  fails while applying `dev.flutter.flutter-gradle-plugin`, before any of our
  code runs.
- `PREFER_SETTINGS` does apply, but it *ignores* project repositories rather
  than failing on them — which silently removes Flutter's engine repository and
  makes every `io.flutter:*` artifact unresolvable. Restoring it means
  replicating `FlutterPlugin.kt`'s derivation (`FLUTTER_STORAGE_BASE_URL`, the
  default host, and the realm read from `bin/cache/engine.realm`) in our own
  settings file, i.e. coupling the build to Flutter internals.

Checksum pinning covers the substitution risk without that coupling, and covers
more ground: a repository added by a plugin cannot substitute a known artifact
(the checksum would not match) nor introduce an unknown one (it is not in the
file), and unlike `repositoriesMode` it also governs the buildscript classpath.

The residual difference is that such a repository is still *contacted* —
checksums reject its bytes, they do not stop the request. With only `google()`,
`mavenCentral()` and `gradlePluginPortal()` declared and no authenticated
repository anywhere in the tree, that leaks nothing beyond the dependency
coordinates themselves. Revisit this trade-off if a private or credentialed
repository is ever added, because then the request itself would carry
something worth protecting.

`.forgejo/workflows/ci.yml` enforces all of this on every branch push:
`tool/check_dependency_verification.py` for the policy half, and a Gradle
resolution of the release classpaths for the checksum half, with
`-Dorg.gradle.dependency.verification=strict` forced so a stray property cannot
switch verification off. That is an early warning covering what the app links
against, not a replacement for the full verification a release build performs.

One limit of that arrangement is worth stating plainly. CI and the release job
share one persistent runner, one `$HOME/flutter-$VERSION` SDK and the default
`~/.gradle`. CI runs on every branch push and executes the workflow file *from
the pushed branch*, so anything with push access can run code on the machine
that later decodes the signing keystore. Dependency pinning does not close that:
it covers resolved Maven artifacts, not a Gradle init script dropped in
`~/.gradle/init.d`, nor the SDK's working tree (the setup step checks which
commit `HEAD` points at, not that the tree is unmodified — and a used SDK is
never clean, since Flutter rewrites its own `pubspec.lock`). For a
single-maintainer repository that is an acceptable trade for the shared caches.
It stops being acceptable the moment anyone else can push, and the fix then is
an ephemeral or separate runner for CI, not a change to these files.

**Regenerate whenever the resolved dependency set changes** — a `pubspec.yaml`
bump, `flutter pub upgrade`, a Flutter SDK bump, or an AGP/Kotlin/Gradle bump:

```bash
cd android
./gradlew --write-verification-metadata sha256 --refresh-dependencies \
    :app:assembleRelease
```

`--refresh-dependencies` matters: without it Gradle hashes whatever is already
in the local cache, so an artifact that had already been substituted would be
"verified" against itself.

That single invocation covers the debug, profile and release variants and all
three ABIs. Afterwards, confirm the paths CI, F-Droid and developers actually
build still work — they resolve slightly different graphs:

```bash
flutter build apk --release --split-per-abi --target-platform=android-arm
flutter build apk --release --split-per-abi --target-platform=android-arm64
flutter build apk --release --split-per-abi --target-platform=android-x64
flutter build apk --release        # the universal APK CI also publishes
flutter build apk --debug          # what `flutter run` resolves
flutter build apk --profile
```

**The file must stay host-agnostic.** `aapt2` is the one dependency published
per operating system, and Gradle records only the classifier for the host that
generated the file. Left as generated it is Linux-only, so a contributor on
macOS or Windows hits a verification failure on their first `flutter run` — an
error naming `aapt2` with no hint that the cause is their OS. The `osx` and
`windows` entries are therefore added by hand from `dl.google.com`, marked with
an `origin` that says so. They survive regeneration — a full
`--refresh-dependencies` run is a byte-identical no-op. Only those three
classifiers exist; `osx` is a universal binary covering both Apple Silicon and
Intel.

**After an AGP bump, checking that those entries are still present is not
enough.** `aapt2`'s version string is derived from AGP, so a bump creates a
*new* component containing only a freshly generated `linux` entry, while the old
hand-added `osx`/`windows` entries remain — attached to the superseded version,
and harmless-looking. Re-derive both hashes for the new version:

```bash
V=<new aapt2 version, e.g. 9.0.1-14304508>
B=https://dl.google.com/dl/android/maven2/com/android/tools/build/aapt2/$V
for c in linux osx windows; do
  curl -sSL "$B/aapt2-$V-$c.jar" | sha256sum | sed "s/-/$c/"
done
```

Cross-check the `linux` line against the entry Gradle generated: they must be
identical. That is what makes the other two trustworthy — it demonstrates the
manual download path returns the same bytes Gradle's own resolution did, rather
than asking anyone to take a hand-pasted hash on faith.

**What this does not cover.** Dependency verification governs Maven artifacts
only. The Android SDK, build-tools and NDK come from `sdkmanager` over Google's
own manifests and are not verified here — the NDK matters most, since its
toolchain output is baked into every native `.so`. Dart packages are pinned
separately, by `pubspec.lock` plus `--enforce-lockfile` in both CI and the
F-Droid recipe. The Flutter SDK is pinned by `FLUTTER_COMMIT`, asserted
in `release.yml` — no longer in the recipe; see §2a-recipe. Read "dependency verification is on" as one layer, not as a
verified toolchain.

Note also what a checksum is and is not: this is trust-on-first-use. A hash
asserts "identical to what was resolved when the file was written", not
"published by someone we trust" — a dependency already compromised at generation
time would be pinned as good. `verify-signatures` is off deliberately:
maintaining a trusted-key ring across ~900 components with uneven signing
coverage would cost more than it buys here.

Review the diff before committing rather than accepting it blindly: the whole
point is that a changed checksum is a signal, and regenerating turns every
signal into a silent accept. A checksum that changes for an artifact whose
version did **not** change deserves an explanation before it is committed.

Failures are loud and specific (`Dependency verification failed for
configuration …`, naming the artifact and repository) and Gradle writes an HTML
report under `android/build/reports/dependency-verification/`. If a verification
problem ever blocks a release, `./gradlew --dependency-verification=off` is the
escape hatch for a local diagnosis — never for a published build.

### 2a-recipe. What each field in the recipe means

[`fdroid/com.luminaapps.cairn.yml`](../fdroid/com.luminaapps.cairn.yml) is the
source of truth for the entry submitted to
[fdroiddata](https://gitlab.com/fdroid/fdroiddata) as
`metadata/com.luminaapps.cairn.yml`, after opening an RFP issue (§2a). It is not
used by the app or by our own CI. Because it must stay in canonical form it
carries no comments, so this section is its documentation.

**Listing text is not in the recipe.** Title, descriptions, changelogs and
screenshots are imported by F-Droid from
[`fastlane/metadata/android/`](../fastlane/metadata/android/) in this repo.
Changelogs are per *versionCode*, so an ABI-split release needs one file per
split code per locale — six files for three ABIs across en-US and de-DE.

**`Repo` / `SourceCode` point at GitHub, not the Forgejo origin.** F-Droid needs
a publicly clonable git repo carrying the release tags; the public, user-facing
mirror is GitHub.

**`AutoName: Cairn`** is the launcher label. F-Droid reads it out of the *source*
`AndroidManifest.xml` at the tag — `checkupdates` calls `fetch_real_name()`,
which parses the manifest; no APK is built for this check. It is committed so
that `fdroid checkupdates --auto`, which fdroiddata's CI runs before diffing, is
a no-op. The listing's display title is separate and comes from fastlane's
`title.txt` ("Cairn: Health Aggregator").

**Three `Builds` blocks, one per ABI.** F-Droid resolves each block's `output` to
exactly one APK, so a single block with a glob matching all three splits fails
with *"Multiple apks match"*. Each block instead builds only its own ABI via
`--target-platform`. That still produces a split APK, so the `versionCodeOverride`
in [`android/app/build.gradle.kts`](../android/app/build.gradle.kts) applies.

**Version codes are `base × 10 + {1,2,3}`** — armeabi-v7a = 1, arm64-v8a = 2,
x86_64 = 3, so build 8 gives 81/82/83. They must match the gradle `abiCodes` map
and the `VercodeOperation` list. The codes ascend with ABI capability because
Android installs the highest versionCode a device can run, so a 64-bit device
picks arm64-v8a over armeabi-v7a. The *order* the `VercodeOperation` entries
appear in is not a tool requirement — `checkupdates` sorts the results and takes
the highest.

**The three blocks repeat `srclibs`/`rm`/`sudo`/`prebuild`/`scandelete`
verbatim, deliberately.** Do not try to factor them out with YAML anchors:
`rewritemeta` expands anchors back into full repeated blocks, so the
de-duplication would silently vanish in the submitted copy and reappear as a CI
formatting diff.

**Each block carries its own `binary:`, rather than one app-level `Binaries:`.**
A shared template can only substitute `%v` (versionName) and `%c` (versionCode);
there is no ABI placeholder. Sharing one would force the published assets to be
named by version code, which tells a human nothing about which file their device
needs. Per-block URLs let the releases stay named by ABI — the version codes
are declared in the recipe but appear nowhere in the published filenames, which
carry `%v` (the version name) and the ABI instead.

**`commit:` pins a full hash by choice, not by requirement.** fdroidserver has no
validator for the field, and `lint` objects only to branch names, so a tag would
be accepted, and a large minority of fdroiddata recipes do use tags. We pin the
hash because tags are mutable and a repointed one would silently change what
gets rebuilt.

The `prebuild:` steps used to apply the same reasoning to the Flutter SDK,
asserting the checked-out tag resolved to `FLUTTER_COMMIT`. The fdroiddata
reviewer asked for that line to go, and conceding it costs little: the identical
assertion still runs in [`release.yml`](../.forgejo/workflows/release.yml),
which is the side holding the signing key, and on F-Droid's side a moved
upstream tag still fails closed — the rebuild simply stops matching the
reference binary. What is lost is only the diagnosis: an obvious toolchain error
becomes an unexplained reproducibility failure. If verification ever fails for
no visible reason, check whether the Flutter tag moved before looking anywhere
else.

That backstop is not an assumption. Pointing one block's `binary:` at the wrong
ABI's APK, so the rebuild could not possibly match, ends the build with
*"compared built binary to supplied reference binary but failed"* and a non-zero
exit — nothing is published. Worth knowing precisely because so much of the
argument for conceding checks elsewhere rests on it.

**Why the seed is the v0.2.3 commit.** It is the earliest tag whose published
APKs can actually be verified. v0.2.2 introduced the per-ABI assets and the
build-path and build-id fixes, but its binaries still carried AGP's
dependency-metadata signing block, which F-Droid's scanner rejects outright, so
verification never took effect. Tags before v0.2.2 published only a universal
APK.

**The `mv`/`pushd` round trip clears its target first.** Moving onto an
existing `/build/cairn` would nest the checkout inside it
(`mv src existing-dir`) and silently build the wrong tree. An earlier version
guarded this with a conditional; the reviewer asked for fewer checks, so it is
now a plain `rm -rf /build/cairn` before the `mv`.

Know how the two differ. The old conditional could *resume* from a run that died
between the two moves, with the checkout stranded at `/build/cairn` and the
original directory already gone. The new form deletes that stranded copy and
then fails on the `mv`, because the source no longer exists. Both refuse to
build the wrong tree — the old one by resuming, the new one by failing loudly —
but only the old one let you retry without a fresh checkout. That matters solely
for repeated local runs in one buildserver container; F-Droid's own builds get a
fresh VM each time, so nothing is stranded there to begin with.

**`AllowedAPKSigningKeys`** is the certificate F-Droid must find on every
downloaded reference binary, as lower-case hex SHA-256 with no colons — the form
fdroidserver compares against. An upper-case value passes `fdroid lint` and then
fails the build. Obtain it with `apksigner verify --print-certs`; the documented
`keytool -printcert -jarfile` one-liner prints `Not a signed jar file` rather
than a fingerprint on a v2-only APK, which is easy to skim past.
The current fingerprint has been confirmed identical across the v0.1.0, v0.2.1,
v0.2.2 and v0.2.3 release APKs — if it ever differs, the keystore has changed and
§2a-repro's key-custody notes apply.

**`UpdateCheckData` and `VercodeOperation` let new tags be picked up
automatically.** The version lives in `pubspec.yaml`, not the Android manifest or
gradle, so `UpdateCheckData` tells the tag checker how to read the base
versionCode (digits after `+`) and versionName (before it). `VercodeOperation`
declares the per-ABI scheme so `checkupdates` computes the right
`CurrentVersionCode` — the highest of the three.

### 2b. Self-hosted F-Droid repo

Host your own repo (e.g. on `git.fiedler.live` or any static host); users add
the repo URL/QR to their F-Droid client. You sign the APKs; full control, no
review queue.

1. `pip install fdroidserver` (or use the Docker image).
2. `fdroid init` in an empty dir (creates the repo + signing key on first run).
3. Drop your signed release APKs into `repo/`.
4. `fdroid update -c` to generate the index, then publish the `repo/` directory
   over HTTPS.
5. Share the repo URL; updates = new APK + `fdroid update`.

Source: [`fdroidserver` / Setup an F-Droid app repo](https://f-droid.org/en/docs/Setup_an_F-Droid_App_Repo/).

### Cairn F-Droid notes

- `minSdk = 26` (Health Connect). Fine for F-Droid.
- If you bump the `health` package, re-check it pulls in no non-free transitive
  dependency (would block official inclusion).
- Background sync (WorkManager) and `READ_HEALTH_DATA_IN_BACKGROUND` are fine on
  F-Droid — there's no health-data review like the stores.

---

## 3. Sideload / direct APK

The simplest strict channel: a signed APK users install directly (after
enabling "install unknown apps").

1. Ensure `android/key.properties` + keystore are in place (DEVELOPMENT.md §3.3).
2. `flutter build apk --release` (or `--split-per-abi` for smaller downloads).
3. Publish `build/app/outputs/flutter-apk/app-release.apk` on the project's
   releases page (Forgejo/GitHub) alongside the `vX.Y.Z` tag + checksums.
4. **Always sign with the same keystore** — Android refuses updates signed by a
   different key.

This is also the build to feed a self-hosted F-Droid repo (§2b).

### Automated APK release (CI)

[`.forgejo/workflows/release.yml`](../.forgejo/workflows/release.yml) automates
this. On a `vX.Y.Z` tag push it runs on the self-hosted, **bare-metal** `linux`
runner, analyzes + tests, builds the **signed** release APK, and publishes it
(with a SHA-256 checksum) to **two** places, both idempotent and attached to the
tagged commit:

- **GitHub** (the public, user-facing repo, `GH_REPO`) — releases are **not**
  mirrored from Forgejo, so the workflow creates the release on GitHub directly
  via its API. The tagged commit reaches GitHub via the Forgejo push-mirror, so
  the release attaches correctly even if the tag ref hasn't finished mirroring.
- **Forgejo** (`git.fiedler.live`, the repo it runs on) — created via the
  Forgejo API using the run's own server/repo.

F-Droid is unaffected — it builds its own copy from the same tag (§2a).

Required Actions secrets:

| Secret | Purpose |
| --- | --- |
| `GH_RELEASE_TOKEN` | GitHub token (contents: write on `GH_REPO`) — the GitHub release |
| `RELEASE_TOKEN` | Forgejo token (write access to this repo) — the Forgejo release |
| `KEYSTORE_BASE64` | base64 of the release keystore (`base64 -w0 release.jks`) |
| `KEYSTORE_PASSWORD` / `KEY_ALIAS` / `KEY_PASSWORD` | keystore credentials |

**Bare-metal runner notes:** the host must already have `git`, `curl`, `jq`,
`base64` and `sha256sum` (there is no container to install them into). Because
the workspace and disk persist between runs, the keystore + `key.properties` are
removed in an `always()` cleanup step, and `actions/checkout` (`git clean
-ffdx`) wipes any leftover artifacts at the start of the next run. Set `GH_REPO`
at the top of the workflow to your GitHub `owner/repo`. The Flutter version is
pinned in the workflow and is the single source the F-Droid recipe reads (§2a).

---

## 4. Google Play Store

Possible, but read the **policy tension** below first — DESIGN.md §10.3 treats
Play as optional, not the primary channel.

### Prerequisites
- Google Play Console account (one-time **$25** registration; identity
  verification required).
- Public privacy-policy URL (§1).

### One-time setup
1. Create the app in Play Console; choose Play App Signing (Google holds the app
   signing key; you keep an upload key).
2. Fill the **store listing**, content rating, and **Data safety** form
   (declare that health data is read, stored in the user's Nextcloud, not
   shared, not sold).
3. Complete the **Health apps declaration** / **Health permissions**
   declaration: justify each `android.permission.health.*` type — *why* it's
   needed, the *user benefit*, and the *privacy/security* measures. This is
   required for every publishing request (new app **and** updates that change
   data types), and `READ_HEALTH_DATA_IN_BACKGROUND` gets specific scrutiny.

### Per release
1. `flutter build appbundle` (Play requires an `.aab`).
2. **Target API level:** since **31 Aug 2025**, new apps and updates must
   **target Android 15 (API 35)** or higher (confirm the current floor — it
   rises ~yearly). This is a recurring treadmill: each year bump
   `targetSdk` + re-test.
3. Upload to an **internal → closed → open** testing track, then promote to
   production.
4. Re-confirm the Health declaration + Data safety if anything changed.

### Cairn gotchas — the health-policy tension
Google Play restricts using health-permission data with apps that **sync health
data between platforms/devices** and restricts **headless/background** access.
Cairn's "funnel HealthKit + Health Connect into the user's own Nextcloud" +
background sync sits awkwardly with the letter of this policy. To reduce
friction: frame the listing as **personal backup/aggregation into the user's
own storage** (not a cross-device sync service for third parties), give strong
per-permission justifications, ship prominent in-app disclosure + affirmative
consent, and request the minimum permission set. If the declaration is rejected,
F-Droid/sideload remain the clean path.

Sources: [Publish your health app](https://developer.android.com/health-and-fitness/health-connect/publish),
[Android health permissions guidance/FAQ](https://support.google.com/googleplay/android-developer/answer/12991134),
[Health content & services policy](https://support.google.com/googleplay/android-developer/answer/16679511),
[Target API requirement](https://developer.android.com/google/play/requirements/target-sdk).

---

## 5. Apple App Store

### Prerequisites
- **Apple Developer Program** membership (**$99/year**).
- A **Mac with Xcode** (no way around this for building/signing iOS).
- Public privacy-policy URL (§1).

### One-time setup
1. Register the bundle id `com.luminaapps.cairn` and enable the
   **HealthKit** capability/entitlement.
2. Create the app record in **App Store Connect**; configure signing
   (automatic, or manual with a distribution certificate + provisioning
   profile).
3. Confirm `NSHealthShareUsageDescription` is set (it is) and reads clearly —
   App Review checks the prompt copy.
4. Fill **App Privacy** ("privacy nutrition label") details and link the privacy
   policy.

### Per release
1. `flutter build ipa` (or archive in Xcode) → upload via Xcode/Transporter.
2. Distribute via **TestFlight** for beta, then submit for **App Review** →
   release.
3. Bump the build number every upload.

### HealthKit review rules (App Store Review Guidelines §1.4.1, §5.1.3)
- A **privacy policy detailing health-data use is required**.
- Health/fitness data **may not be used for advertising, marketing, or data
  mining** — only health management (or research with permission).
- **Apple Health data may not be stored in iCloud.** Cairn stores in the
  **user's own Nextcloud**, which is fine — it's *Apple's* cloud that's barred.
- No medical-device/diagnostic claims. Background delivery (`BGAppRefreshTask`)
  should be justified by the sync purpose.

Sources: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
[App Privacy details](https://developer.apple.com/app-store/app-privacy-details/),
[Protecting access to health data](https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web).

---

## 6. Nextcloud App Store (the PHP + Vue app)

The optional Nextcloud web app (DESIGN.md §7), distributed via
[apps.nextcloud.com](https://apps.nextcloud.com/) and installed by self-hosters
onto their own instance. **AGPL-3.0-or-later** — see `docs/DEVELOPMENT.md` §5
for why that is not the same reason people usually give.

### Build a release

```bash
nextcloud_app/dev package          # -> nextcloud_app/build/cairn-<version>.tar.gz
nextcloud_app/dev verify-package   # install it on a clean Nextcloud and drive it
```

`package` builds the frontend, stages the release and packs it. Three things
about how it does that are deliberate:

- **The contents come from an allowlist** (`PACKAGE_PATHS` in
  `nextcloud_app/dev`), not an exclude list. An exclude list ships whatever
  nobody thought to exclude — a stray `.env`, a signing key, an export somebody
  left in the tree. An allowlist can only *omit* something, and that fails
  visibly the first time the app is installed.
- **There is no `vendor/`.** The app has no runtime dependencies: `composer.json`
  requires only a PHP version, and Nextcloud autoloads `OCA\Cairn` from `lib/`
  itself. What ships is first-party code and the built bundle, with nothing
  underneath it to audit.
- **The tarball is reproducible** — fixed timestamps, owner and sort order, so
  the same input produces the same bytes. Same reasoning as the F-Droid builds
  in §2: an artefact nobody can reproduce is one nobody can check.

`verify-package` is the half that matters. It unpacks the tarball into a *clean*
Nextcloud — using `docker/compose.verify.yaml`, which deliberately has **no bind
mount of the working tree**, or the check would exercise the code on disk while
appearing to exercise the artefact — then enables the app and drives the page,
the bundle and all six endpoints. It also asserts no `tests/`, `src/`, `docker/`
or `vendor/` came along. Packaging that has only been *inspected* has never been
tested; the failure mode is a missing file nobody notices until somebody else
installs it.

### One-time setup: the signing certificate

App Store releases are cryptographically signed, so this is needed before the
first upload and never again:

1. Generate a keypair, by convention under `~/.nextcloud/certificates/`:
   ```bash
   openssl req -nodes -newkey rsa:4096 -keyout cairn.key -out cairn.csr -subj "/CN=cairn"
   ```
2. Open a PR adding `cairn.csr` to
   [`nextcloud/app-certificate-requests`](https://github.com/nextcloud/app-certificate-requests).
   Open it **from the `LuminaAppsDev` account**, which is where releases come
   from and what `info.xml`'s `<bugs>` and `<repository>` point at. That account
   needs `luminaapps@gmail.com` as a **public** email: ownership is verified
   against it, and it is the same address `info.xml` publishes to everyone who
   installs the app. `tests/validate_info_xml.php` asserts that address, so it
   cannot quietly drift back to a personal one.
3. When it is counter-signed, save the returned `cairn.crt` beside the key, and
   register the app id on the App Store — the form asks for the certificate and
   a signature over the app id, proving you hold the private key. Register from
   the same account, so the store listing, the issue tracker and the source all
   name one owner.

> **The private key never enters this repository.** `.githooks/pre-commit`
> refuses `*.key`, `*.pem` and `*.p8` outright, alongside the Android signing
> material. The `.crt` is public and may be committed. Keep the key where the
> tooling expects it, or point `CAIRN_SIGN_KEY` and `CAIRN_SIGN_CERT` at it.

With a certificate present, `dev package` additionally writes
`appinfo/signature.json` into the tarball (Nextcloud's integrity check, via
`occ integrity:sign-app`) and prints the base64 detached signature the upload
form asks for. Without one it says so and produces an unsigned tarball, which
installs from disk but will not be accepted by the store.

### Publish

1. Bump `<version>` in `nextcloud_app/appinfo/info.xml`.
2. Confirm the compatibility claim: `nextcloud_app/dev matrix` (§7).
3. `nextcloud_app/dev package && nextcloud_app/dev verify-package`.
4. Attach the tarball to a release so it has a stable download URL.
5. Upload via the App Store's REST API or the "Upload release" web form, giving
   the download URL and the printed signature.

`krankerl` is the usual tool for steps 3–5 and is a reasonable alternative. It
is deliberately not used here: it is another binary to install, and the whole
point of this dev environment is that Docker is the only prerequisite.

Sources: [App Store developer guide](https://nextcloudappstore.readthedocs.io/en/latest/developer.html),
[Code signing](https://docs.nextcloud.com/server/stable/developer_manual/app_publishing_maintenance/code_signing.html),
[Release automation](https://docs.nextcloud.com/server/latest/developer_manual/app_publishing_maintenance/release_automation.html),
[krankerl](https://github.com/ChristophWurst/krankerl).

---

## 7. Keeping the Nextcloud app current (version-tracking maintenance)

This is the **accepted maintenance tax** of the Nextcloud path (DESIGN.md §7,
§14): an app whose `info.xml` `max-version` is below a newly-installed Nextcloud
major is **automatically disabled on upgrade** until you publish a compatible
release. Self-hosters upgrade on their own schedule, so a stale app silently
disappears for them.

**Check the claim, do not assert it.** `nextcloud_app/dev matrix` installs every
Nextcloud major `info.xml` names, enables the app and drives it, plus parses
every file under the declared PHP floor — which none of the Nextcloud images
ships, so that half would otherwise go untested while looking covered. Run it
before every release. `info.xml`'s range, the `MATRIX_IMAGES` table in
`nextcloud_app/dev` and `docker/compose.yaml`'s default image are one claim
written three times; move them together.

**Cadence.** Nextcloud ships roughly **three major releases per year** (e.g. 30,
31, 32…). Each has a developer **"Upgrade to Nextcloud NN"** guide listing
breaking changes and removed APIs.

**Per new major — the routine:**
1. Read the **[Upgrade to Nextcloud NN](https://docs.nextcloud.com/server/latest/developer_manual/app_publishing_maintenance/app_upgrade_guide/)**
   guide for that release.
2. Spin up a dev instance on the new major (DEVELOPMENT.md §4.2) and run the
   app; fix any deprecations/removals.
3. Run **`occ app:check-code <appid>`** to catch use of private/removed APIs.
4. Bump `info.xml` `<nextcloud max-version="NN"/>` (and the `<php>` range if the
   new major moved its PHP floor).
5. Bump the app `<version>`, re-sign, and upload a new release (§6 / `krankerl`).
6. Keep a **CI matrix** building/testing the app against the supported Nextcloud
   majors so breakage surfaces before users hit it.

Because the app is **read-only over the `/Cairn/` files** and never authoritative
(DESIGN.md §7), a lapse is low-stakes: users keep their data and the mobile app;
they just lose the optional web frontend until the next compatible release.

---

## 8. Channel decision (recap)

| Channel | Effort | Health-policy friction | Recommendation |
| --- | --- | --- | --- |
| **F-Droid** (official + self-hosted) | Medium | None | **Primary** — the clean strict path |
| **Sideload / direct APK** | Low | None | Always provide |
| **Google Play** | High | High (cross-platform-sync tension) | Optional; scope listing carefully |
| **Apple App Store** | High (needs Mac + $99/yr) | Medium (HealthKit rules) | Optional; for iOS reach |
| **Nextcloud App Store** | Medium | None | Phase 7, when the web app exists |

See also: [`DESIGN.md`](DESIGN.md) §10 (privacy/compliance) and §15 (phases);
[`DEVELOPMENT.md`](DEVELOPMENT.md) for build/signing setup.
