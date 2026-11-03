# Changelog

All notable changes to this project are documented in this file.

## Unreleased

### Added

- **Cairn asks for Health Connect's history permission along with the
  reads.** Without `READ_HEALTH_DATA_HISTORY`, Health Connect serves only data
  from 30 days before Cairn's first grant on. It clamps every read to that
  date without an error, so a catch-up over an older gap read as empty and
  moved its anchor past the data for good. That first grant resets once Cairn
  holds no health permission at all, for example after Android revokes
  permissions of an unused app. Both facts were verified in the AOSP source.

  The read-permission request now also asks for history while it's missing,
  in the same flow and before any read, so a re-grant brings it back before
  the catch-up runs. Health Connect shows nothing when everything is already
  granted, and stops asking after two declines. Settings has an "Older data"
  row on Android that shows whether it's allowed, missing or unsupported, and
  offers **Allow**. The Settings rows for background reads and history share
  one status type, `ReadAccessStatus`, which replaces `BackgroundReadStatus`.
  Patch 3 of the vendored plugin now also guards the two history status
  checks, which would otherwise crash the process on a binder failure.

- **Background sync asks for Health Connect's background-read permission.**
  Cairn declared `READ_HEALTH_DATA_IN_BACKGROUND` but never requested it, so
  background sync could never read. It now asks once on its own, on the first
  foreground refresh where reads are granted and this one is missing. It asks
  only after that refresh has read and uploaded, so an open sheet holds
  nothing up. The ask is remembered per device, and so is a grant found
  already in place, so a later deliberate revoke isn't answered with a prompt.
  Settings has a "Background sync" row on Android that shows whether reading
  in the background is allowed, missing, or not supported by this Health
  Connect, and re-checks when you return to the app. When it's missing, an
  **Allow** button asks again. If Health Connect has stopped showing its
  sheet after repeated denials, the button opens Health Connect's settings
  instead, where the user can turn it on under Cairn → Additional access. Permission sheets now open one at a time,
  because the plugin can only track one at once.

- **The counter-signed code-signing certificate, committed at
  `nextcloud_app/cairn.crt`.** It carries nothing secret, and keeping it in the
  repository means anyone can verify a release signature against the same
  certificate the app store used. `dev package` now finds it there by default,
  so the private key — which never enters this repository, and which
  `.githooks/pre-commit` refuses — is the only secret the release path needs.

  `tests/validate_certificate.php` checks it on every `dev check`, for two
  failures that are otherwise quiet until they are expensive. A certificate
  naming a different app id produces signatures the store rejects at upload,
  long after the release was cut. And expiry is a time bomb: this one is good
  until 2036, so nothing goes wrong until one day releases stop being accepted
  and nobody remembers why — the check warns 90 days out. It also refuses the
  file outright if a private key ever appears in it, and says so in those words,
  because that file is public. All three were verified by planting each mistake
  in turn.

### Changed

- **The vendored `health` plugin is rebased onto upstream 13.3.2.** Patches
  1–3 carry over unchanged, because upstream left both patched Kotlin files
  alone; patch 4's formatting re-applies to `health_plugin.dart`, which
  matches upstream token for token. 13.3.2 adds write-and-return-UUID APIs,
  which Cairn never calls, and moves the iOS sources to a Swift package
  (`ios/health`; the plugin class is now `HealthPlugin`, not
  `SwiftHealthPlugin`). It needs `device_info_plus` 13 and
  `carp_serializable` 3, which bring win32 6 (Windows only). That unblocks
  flutter_secure_storage 11. The Maven graph is unchanged: regenerating
  `verification-metadata.xml` added no pins.

  The iOS deployment target rises from 14.0 to 15.0, the plugin's new floor,
  in the `Podfile`, `Runner.xcodeproj` and `AppFrameworkInfo.plist`.
  iOS 15 runs on every device iOS 14 does. `docs/DEVELOPMENT.md` §3.4
  still said 13.0 and now says 15.0.

- **Flutter 3.47.9 (Dart 3.13.7), up from 3.44.0.** Bumped together in
  `.fvmrc`, `release.yml` (`FLUTTER_VERSION` and `FLUTTER_COMMIT`), and
  `docs/DEVELOPMENT.md`; the SDK floor in `pubspec.yaml` is now `^3.13.0`. The
  SDK's own pins moved intl to 0.20.3, meta to 1.19.0 and vector_math to
  2.4.4, and the test-only matcher and test_api to 0.12.20 and 0.7.12.
  very_good_analysis 11 and xml 7.1, which need Dart 3.13, come along:
  - very_good_analysis 11 enables `unnecessary_type_name_in_constructor`, so
    constructors use Dart 3.13's `new` form (`const new(...)`), applied by
    `dart fix` across 61 files. It also enables `async_return_with_no_await`;
    the 11 hits now `return await`. None sits in a `try`, so error handling is
    unchanged; the returning function now shows in async stack traces.
  - xml 7.1 brings petitparser 7.1.0 and deprecates
    `findAllElements(namespace:)` for `namespaceUri:`. It is an alias, so the
    PROPFIND parser matches exactly as before.
  - The Dart 3.13 formatter reflowed 34 files.
  - `verification-metadata.xml` swaps the 12 `io.flutter` engine pins from
    the 3.44 engine (`4c525da`) to engine `89c39ed`. Gradle only adds pins,
    so the old ones were removed by hand; `docs/RELEASE.md` §2a-deps now says
    so for future SDK bumps.

- **Dependencies upgraded within their existing constraints.** fl_chart
  1.3.0, flutter_secure_storage 10.3.4, path_provider 2.1.6, url_launcher
  6.3.3, uuid 4.6.0, plus their transitive packages. Two of those cross a
  major version: equatable 3.0.0 (via fl_chart) and package_config 3.0.0. Regenerating `verification-metadata.xml` with
  `--refresh-dependencies` added no pins. `pubspec.yaml` now pins
  `workmanager_android` to 0.9.0+2, so workmanager stays at 0.9.0+3: 0.9.0+3
  through 0.9.3 skip the Kotlin plugin on AGP 9 without checking
  `android.builtInKotlin`,
  which the Flutter template sets to `false`, so its plugin class is never
  compiled and the APK build fails. 0.10.x checks the flag. Major bumps
  (flutter_secure_storage 11, workmanager 0.10) follow separately.

- **The `health` plugin is vendored at `third_party/health`, with a small
  patch.** Upstream's Android reader returns an empty list when a read fails,
  or when the type's permission is missing at read time. The latest release,
  13.3.2, still does. Callers can't tell that from "no data", so the patch
  reports both as errors. It is the copied 13.3.1 release plus those two hunks
  and a one-time `dart format` of four files. `CAIRN_PATCHES.md` next to it
  records the upstream hash, the hunks, and how to upgrade. The copy is a path dependency, so F-Droid's `pub get
  --enforce-lockfile` builds it from this repository with no extra host.

- **Phase 7 is complete: the Nextcloud web app is published on the app store.**
  `docs/DESIGN.md` §15 records the exit criteria as met — it installs on a
  user's own Nextcloud, renders aggregates from `/Cairn/`, and never writes.

- **The release pipeline now runs the same gate as CI.** `release.yml` checked
  formatting not at all and ran a bare `dart analyze`, which exits 0 on
  info-severity diagnostics — and most `very_good_analysis` rules are
  info-severity, so a release could ship exactly what CI rejects. It also ran
  `flutter test` without `--no-pub`, leaving room for an implicit resolution
  that would not carry the `--enforce-lockfile` of the step above it; on the
  workflow that builds the reference binary, the dependency set must be the
  locked one or nothing.

  The format gate matters more than it looks. `ci.yml` fires on branch pushes
  and never on a tag, so a commit tagged without first landing on a branch — or
  tagged before its branch run finishes — reached a release with no format check
  at all. All three checks are source-only and run before the APK steps, so none
  of them can move the bytes F-Droid rebuilds.

- **The F-Droid recipe carries 0.3.0.** Three `Builds:` blocks appended, one per
  ABI, at version codes 91/92/93 — `base × 10 + {1,2,3}`, matching the
  `abiCodes` map and the `VercodeOperation` list — pinned to the full hash of
  the commit tagged `v0.3.0`. The 0.2.3 blocks stay: fdroiddata keeps every
  released version so an old tag remains rebuildable, and 0.2.3 is the seed, the
  earliest tag whose published APKs can be verified at all.

  The new blocks repeat the build steps verbatim rather than sharing them, which
  is deliberate and documented — `rewritemeta` expands YAML anchors back out, so
  any de-duplication would vanish from the submitted copy and return as a CI
  formatting diff.

- **Do not check the recipe's format with a local `fdroid rewritemeta`.** Every
  `binary:` field wraps its URL onto a continuation line, leaving a trailing
  space after the colon. That looks like a defect and is not: it is exactly what
  fdroiddata's CI emits, because `rewritemeta` sets no explicit YAML width, so
  ruamel's 80-column default applies and the only break point in a long
  `binary: <url>` line is the space after the key.

  A locally installed fdroidserver need not agree. Ours (2.4.5 on ruamel
  0.17.21) declines to break after a key and writes the URL inline, so running
  it "canonicalised" all six fields into the one form their CI rejects — which
  is how this was found: their pipeline failed on the diff. The wrapped form is
  restored, and the three 0.3.0 blocks are byte-identical clones of the accepted
  0.2.3 ones.

  The rule that follows: for this file, fdroiddata's CI is the authority on
  format, not whatever `fdroid` happens to be on `PATH`. A local run is only
  evidence if the ruamel version matches theirs.

### Fixed

- **Ingest failures are now classified, and a stuck metric is named.**
  Before, every failed read counted as the same retry-later failure. A plugin
  fault, such as a record the plugin's converter can't handle, was never
  reported as a bug, even though it fails the same way every run. After a
  Health Connect rate limit, the remaining metrics still read and spent more
  of the quota. And the message named no metric, so a metric stuck every run
  went unnoticed.

  The vendored plugin now passes the native exception's class and Health
  Connect's platform error code with a failed read. The client folds several
  codes, the rate limit among them, into one Kotlin class, so the class alone
  can't tell them apart. `HealthReadException.failure` sorts each failure into
  one of three kinds:
  - **Transient:** the store's own trouble, retried next refresh.
  - **Rate limited:** ends the run after its metric, like a missing store.
  - **Unexpected:** a plugin fault, or a request Cairn got wrong. Reported as
    a bug in the log. Anything unrecognised also counts as unexpected; a
    misjudged one costs only a log entry.

  A failing metric is still held, never skipped, so once a fix ships nothing
  is lost. `ingest` now returns one result per metric: those a run-ending
  failure left unread carry its error. The snackbar and Settings name the
  metrics that weren't read or saved, for example "Could not read or save:
  Heart rate, Steps." / "Lesen oder Speichern fehlgeschlagen: Puls,
  Schritte."

- **One failure anywhere in ingest abandoned the whole refresh.** Only a
  failed *read* was isolated per metric. Any other error in one metric ended
  the refresh early, for example a bug in mapping or a bad record. The metrics
  after it weren't ingested, the screens didn't reload, and nothing was
  uploaded, not even files already on disk from earlier runs.

  Now a metric's own failure stops only that metric. `IngestResult` carries
  the error and its stack, the anchor holds, the next refresh retries it, and
  the rest still ingest. Each distinct bug is reported once, even when a
  shared fault fails every metric. Two failures that aren't one metric's own
  end the run after it: Health Connect missing, and a local storage error
  (`FileSystemException`, e.g. a full disk), where every further write would
  only tear another shard. An append after a torn tail now starts on a fresh
  line, so the first new record can't be glued onto the fragment and lost.

  The upload now runs even when reading failed, so earlier files still go up.
  The one exception is a missing Health Connect, which gets an immediate
  answer and no pointless push. The upload failure's message says "saved
  locally", so it is shown only if something was saved; otherwise the read
  failure wins. That message now reads "Could not read or save health data."

- **Background sync read Health Connect without permission.** Health
  Connect's reference says a background read without
  `READ_HEALTH_DATA_IN_BACKGROUND` "may result in an error". Since failed reads
  stopped being swallowed that lost no data, but every WorkManager run spent
  its reads and ended in `readFailed`. A background run now checks the
  permission first. Without it, the run skips reading and only uploads, and the
  next foreground refresh catches up from the anchors.

- **A background sync could tear the manifest under a foreground one.** The UI
  and the WorkManager / BGTaskScheduler isolate each build their own services.
  The in-isolate guards (the refresh single-flight, the store's manifest lock)
  never saw the other isolate. Two refreshes could therefore interleave writes
  through the same fixed `.tmp` paths. A torn `manifest.json` reads as empty
  and drops every anchor, and mid catch-up that loses the unread gap. A shard
  compaction's rename could also drop the other isolate's appends.

  Two layers now, so that neither has to be perfect.

  First, the manifest, shard compaction, sync journal, profile and locale each
  write a temp file of their own, named uniquely per write, and rename it into
  place. Even
  if two writes overlap, each lands whole and the last one wins. The worst case
  is a lost update, which costs a deduplicated re-read. Temp files are never
  uploaded, and those a crash leaves behind are swept at startup once they are
  an hour old.

  Second, refreshes take a process-wide lock built on `IsolateNameServer`,
  whose name registration is an atomic test-and-set across isolates. File
  locks can't do this, because POSIX record locks are per process.
  - A foreground refresh waits its turn.
  - A background one skips if a refresh is running, since it would only redo
    that work on a short OS budget.
  - A holder whose isolate died is taken over by either side after two
    unanswered immediate-priority pings, which the VM answers even
    mid-computation. Android destroys a stopped worker's engine without
    running `finally`, for instance when connectivity drops mid-sync.
  - A foreground refresh takes over a holder that is alive but hung only after
    15 minutes. That is longer than any legitimate background hold (WorkManager
    stops a worker after 10 minutes), so a slow but working sync is never
    overlapped. A shard compaction's rename would otherwise drop the other
    refresh's appends.

  WebDAV responses also got an idle timeout on their body, not just their
  headers. It cancels a stalled stream instead of leaving the connection
  buffering.

- **A failed health read was treated as "no data", and its span was never read
  again.** Two layers turned a failed read into an empty list. The `health`
  plugin's Android reader caught every exception, and Cairn's own repository
  mapped every `PlatformException` to `[]`, which on iOS covers HealthKit's
  locked-device error. Ingest then moved the anchor past readings it never
  got. Anything older than the 14-day reconcile window was gone for good: a
  Health Connect rate limit during a catch-up, a permission revoked mid-run, or
  a background read the store refused.

  A failed read now throws `HealthReadException`. The failing metric keeps its
  anchor at the last finished slice, so the next refresh retries from there.
  The remaining metrics still ingest and sync, and the refresh reports
  `readFailed` so the user sees it. Its push report is kept, so the
  conflict-copy warning still shows. A type that keeps failing now says so on
  every refresh instead of silently skipping data. A first run whose read fails
  pins its 30-day window start. Otherwise the retry would compute a start that
  slides forward with the clock, and the oldest days would drop out unread.
  Telling a failure that keeps recurring apart from a passing one is recorded
  in `docs/DESIGN.md` §14.

  The same review found a case that silently skipped workouts. The plugin's
  workout read also reads the distance, calories and steps records inside each
  workout, so a grant missing any of them failed the whole read, which then
  came back empty. Activity now counts as granted only when all of those are
  granted, and steps is requested with it. A partial grant is skipped up front
  with its anchor kept, rather than read into an error on every refresh.

- **Opening the app after a long break crashed it, every time.** Ingest read
  each metric from its sync anchor to now in one call, and the health plugin
  holds a whole read in memory several times over before handing it to Dart.
  After a few months of watch heart rate and steps that ran the process out of
  memory a few seconds after launch. The anchor only moved after a successful
  read, so each relaunch retried the same window and crashed again. Seen on a
  production Pixel; turning off heart rate and steps in Health Connect stopped
  it.

  `HealthIngestService` now reads any catch-up span older than the 14-day
  reconcile window in slices of at most a week, advancing the anchor after
  each. A week is half the window every run already reads in one go. The window
  itself is still one read, so a normal run makes the same calls as before. A
  catch-up killed partway resumes from the last finished slice. A record that
  crosses a slice boundary is read exactly once: Health Connect matches reads
  on a record's start time alone, `start <= t < end`, which we checked in the
  platform source rather than assuming it. Sleep is never
  sliced: its nightly episodes are built per read, so a slice boundary in the
  middle of a night would write two partial episodes, and a few segments a
  night never needs slicing. Five older ingest and sync risks that the review
  turned up are recorded in `docs/DESIGN.md` §14 for follow-up.

- **The new seam tests read the wall clock, so they were true only on the day
  they were written.** Almost every query is defined relative to today, and
  `QueryFactory` built its own `SystemClock` — so a controller test asserting
  today's step total passed on 2026-08-20 and failed on the 22nd. Caught by the
  suite two days later rather than by CI on a quiet morning, which is luck, not
  design.

  `QueryFactory` now takes an injectable clock, for the same reason the query
  service already did, and the seam tests pin the date. Checked that nothing
  else is exposed: the only remaining test that reads the wall clock is the one
  covering `SystemClock` itself, which asserts a delta rather than a date.

- **The release build ran the tests in the runner's timezone.** `ci.yml` pins
  `TZ: Europe/Berlin` because the parity fixtures are authored there and Dart
  takes its zone from the environment; `release.yml` never did. The parity suite
  is new in 0.3.0, so the release path had never met it — 0.2.3 predates it —
  and the first tag that reached it failed on a runner in America/New_York, with
  every sleep night landing a day early. Nothing was built or published: the
  test step runs before the APK steps.

  The pin is scoped to the "Analyze and test" step rather than the workflow
  `env:`, unlike ci.yml. Everything after that step compiles the APK F-Droid
  rebuilds and compares byte-for-byte, and a verification failure publishes
  nothing at all. The build inherits the runner's zone today and verifies
  against a buildserver with its own, so the bytes are evidently
  zone-independent — but only the tests need Berlin, and the one workflow where
  being wrong is silent is not the place to confirm that.

### Security

- **Nothing of Cairn's goes into Android backups or device transfers any
  more.** The manifest never set `allowBackup`, so Android Auto Backup copied
  the app's private files, including the local OMH health cache and the sync
  journal, into the user's Google Drive. The user's own Nextcloud is supposed
  to be the only copy. `allowBackup="false"` stops the cloud backup.
  `data_extraction_rules.xml` excludes everything from device-to-device
  transfer too, which `allowBackup` alone doesn't cover on Android 12+. After
  a reinstall the cache rebuilds from Health Connect and the profile comes
  back from Nextcloud. The app token never survived a restore anyway.

## 0.3.0 — 2026-08-22

### Added

- **Tests for the Nextcloud-facing seam — the half that had none.** The read
  path was covered from the first commit; everything that touches the server was
  covered only end-to-end, by the compatibility matrix and the packaged-app
  check. Those prove the whole thing works and say nothing about *which* branch
  handled a missing folder, a torn line or another user's session. Untested
  classes went from 17 to 7, and the seven are a no-op bootstrap and plain data
  holders.

  The controllers are tested against the **real** stack — `QueryFactory`,
  `NextcloudShardSource`, `DashboardAssembler`, `OverviewService` are all
  production classes here, with doubles only for the two things that genuinely
  cannot exist without a server: the filesystem and the session. That was forced
  by making them `final` and turned out better than mocking them, because a
  request in a test now travels the same path a real one does. Files are backed
  by real in-memory streams, so `fopen()` and the 64 KiB line cap are exercised
  rather than stubbed past.

  What that pinned down, one branch at a time: a window outside the limits is
  rejected rather than clamped, and the limits themselves are accepted; nights
  are capped tighter than days because they cost more per unit; every endpoint
  answers on an empty folder, because an empty folder is a normal state and not
  an error; a request reads the session user's files and another user reads
  nothing; `$day` is validated by `readShard` itself rather than by its caller;
  an over-long line is skipped once rather than once per chunk; blank lines are
  separators, not damage. And in the assembler, the two averaging rules that
  change what a number *means* — the step average ignores days that never
  reported, so a gap does not read as inactivity, and the heart-rate mean is
  weighted by sample count, so a day with three readings does not outvote one
  with three hundred.

  `tests/bootstrap.php` loads the `OCP` interfaces from `nextcloud/ocp`, which
  publishes them as PSR-4 sources but declares no autoload section, being
  intended for static analysis. Pinned to the lowest Nextcloud the app claims,
  for the same reason psalm analyses against it. `tests/stubs/` fills the one
  gap that leaves: `IRootFolder` extends `OC\Hooks\Emitter`, which lives in the
  server's private namespace and is not shipped. Adding it made psalm's
  `MissingDependency` suppression unnecessary, so that is gone too — one fewer
  place where an analyser was told to look away.

  Two bugs in the test helpers themselves are worth recording, because both are
  traps this codebase already documents. PHP coerced the year folder `"2026"`
  into `int 2026` — the exact numeric-key coercion `StrictJson` exists to avoid,
  met in a helper rather than in the reader. And the storage doubles were mocks
  when they should have been stubs: the tests care what storage *returns*, never
  how often it was asked, and a mock would fail whenever the reader was made
  more efficient.

- **App-store packaging: `dev package` and `dev verify-package`.** The release
  tarball's contents come from an **allowlist**, not an exclude list, and that
  is the point of it: an exclude list ships whatever nobody thought to exclude —
  a stray `.env`, a signing key, an export left in the tree — while an allowlist
  can only *omit* something, which fails visibly on first install. It carries no
  `vendor/`, because the app has no runtime dependencies at all: `composer.json`
  requires a PHP version and nothing else, and Nextcloud autoloads `OCA\Cairn`
  from `lib/` itself. 140 KB, 68 files, byte-identical across builds — fixed
  timestamps, owner and sort order, the same reasoning as the reproducible
  F-Droid builds in `docs/RELEASE.md` §2.

  `verify-package` is the half that matters, because packaging that has only
  been inspected has never been tested. It unpacks the tarball into a **clean**
  Nextcloud and drives the page, the bundle and all six endpoints, then asserts
  no `tests/`, `src/`, `docker/` or `vendor/` came along. It uses a compose file
  with **no bind mount of the working tree** — with the ordinary one,
  `custom_apps/cairn` *is* the working tree, so the check would exercise the
  code on disk while appearing to exercise the artefact, and a missing file
  would pass. Verified to fail: dropping `templates` from the allowlist produces
  a tarball that installs, enables, and then cannot render a page — reported as
  exactly that.

  Signing is wired up but inert until a certificate exists. With one present the
  run writes `appinfo/signature.json` via `occ integrity:sign-app` and prints the
  detached signature the upload form wants, deleting the key from the container
  afterwards; without one it says so and produces an unsigned tarball, which
  installs from disk but will not be accepted by the store. `krankerl` is the
  usual tool here and is deliberately not used: it is another binary to install,
  against a dev environment whose whole premise is that Docker is the only
  prerequisite.

- **A compatibility matrix, because `info.xml` was making a promise nobody had
  checked.** The app declares `min-version="32" max-version="34"` — a promise to
  everyone installing from the app store — and had only ever run on 34. A stale
  `max-version` is the documented maintenance tax of a Nextcloud app
  (`DESIGN.md` §7): get it wrong and the app is silently disabled on somebody
  else's server after they upgrade.

  `nextcloud_app/dev matrix` installs each claimed major in turn, enables the
  app, seeds generated data, and checks the page, the bundle and all six
  endpoints — plus the read-only guard and `info.xml` under **that version's
  PHP**, which turns out to differ across all three: 32 ships 8.3.33, 33 ships
  8.4.24, 34 ships 8.5.9. All three pass.

  That spread exposed a gap the matrix would otherwise have hidden: `info.xml`
  also declares a PHP floor of 8.2, and **none of the Nextcloud images ships
  8.2**, so half the compatibility claim was untested while looking covered. The
  matrix now parses every file under `php:8.2-cli-alpine` first. It passes, so
  the floor is real rather than aspirational.

  Verified to fail, not just to pass: narrowing `max-version` to 33 makes
  Nextcloud 34 refuse the app, and the run reports `Nextcloud 34 FAILED` and
  exits non-zero with the fix in its message. A check that cannot go red is
  decoration.

  It runs as its own Compose project on its own port and tears each version down
  afterwards, so it cannot disturb — or be disturbed by — a `dev up` instance you
  have open. Confirmed by running it with one open.

- **`.forgejo/workflows/nextcloud-matrix.yml`**, running the same command CI
  users run locally. Deliberately *not* on every push: three Nextcloud installs
  would queue every other job behind them on a single-runner host. It fires when
  the claim or the environment changes, on demand, and weekly as a net for a
  change to `lib/` that broke an older version without touching `info.xml`.

  `info.xml`'s version range, the `MATRIX_IMAGES` table in `dev`, and
  `compose.yaml`'s default image are one claim written three times; the docs now
  say so, because the failure mode is one of them moving alone.

- **Static analysis and a coding standard for the PHP.** Every other language
  in this repository had a real analyser — `dart analyze --fatal-infos`,
  flake8/pylint/mypy, shellcheck — while the app subtree had only `php -l`,
  which is a syntax check and would not notice a null dereference or a wrong
  argument type. `psalm` now runs at level 2 and `nextcloud/coding-standard`
  formats, both wired into `dev lint` and `nextcloud-ci.yml`.

  There is deliberately **no psalm baseline**. A baseline records the mistakes
  that existed when it was written and permits them for ever, which is the
  opposite of what an analyser is for. The three suppressions in `psalm.xml` are
  scoped and carry their reasons: `#[\Override]` is a PHP 8.3 attribute and
  `info.xml` declares 8.2 (matching what Nextcloud 32 supports), so adding it
  would trade an install for a compile-time check; `MissingDependency` is
  confined to the one file holding an `IRootFolder`, because OCP's own interface
  extends a class the published stubs do not ship; and
  `PropertyNotSetInConstructor` is confined to `tests/`, where PHPUnit's
  `setUp()` is the de-facto constructor.

  The stubs are pinned to **Nextcloud 32**, the lowest version `info.xml`
  claims, so calling an API added in 33 or 34 is a finding here rather than a
  broken install for somebody on 32.

  The first run found 59 issues, 13 of them substantive. `dailyHeartRate` built
  per-day lists and reduced them three times, which is why `min()` could not be
  shown to have anything to work on; it now accumulates the spread as readings
  arrive, visiting each value once. `ManifestReader` tested one expression and
  returned another — nothing guarantees the second read of a property sees what
  the first did. `weight()` indexed `$series[count($series) - 1]`, which is
  `$series[-1]` on an empty series; the `??` made it harmless rather than
  correct. `folderChildren()` promised a `list` while returning the keyed array
  the API hands back. The rest were implicit int/float coercions now made
  visible, and ten classes nothing extends are now `final`.

- **The dashboard: a read-only JSON API and a Vue frontend over it.** Six GET
  endpoints — steps, heart rate, weight, sleep, activity, and what is on disk —
  each scoped server-side to whoever is logged in. No route takes a user id, so
  there is none to swap for somebody else's and no permission check that could
  be forgotten. Windows are rejected rather than clamped (`days=0` and
  `days=100000` both return 400): silently answering a different question than
  the one asked turns a frontend bug into a puzzling chart instead of a visible
  error.

  Charts are hand-rolled inline SVG. A charting library would be a large
  dependency, a Content-Security-Policy conversation and a second theming system
  to reconcile with Nextcloud's, in exchange for five charts of two shapes.
  Every colour is a Nextcloud custom property, so they follow a themed instance
  and dark mode without being told. Each metric section carries its own loading,
  error and empty state — one endpoint failing must not blank the others, and an
  empty folder is a normal state that should not look like a broken page.

  The sleep hypnogram draws one row per stage rather than overlaying them, which
  is what makes the whole-night `session` overlap visible at a glance instead of
  only in the numbers.

  German is included, in the phone app's `du` voice and reusing its vocabulary
  (Schritte, Puls, Schlaf, Gewicht) so the two frontends read as one product.
  Numbers, dates and durations are formatted in the browser from ISO instants
  and integer milliseconds — the server sends the unambiguous form, and only the
  browser knows the viewer's locale. Verified end to end: `88,1 kg`,
  `4.704 pro Tag`, `Mittwoch, 19. August`, and the plural form.

- **`dev deps`, `dev build`, `dev watch` and `dev lint`.** Composer and npm run
  in their own pinned containers, so Docker is still the only prerequisite. The
  Node container is 22, not 20: `@nextcloud/eslint-config` imports
  `findPackageJSON` from `node:module`, which does not exist before 22, so 20 is
  simply not a toolchain this app builds on.

- **A parity case for the sleep-total rule.** Samsung Health emits a
  whole-night `session` segment alongside the fine-grained stages, including the
  awake ones, and `session` counts as asleep — so a reader taking only the union
  of asleep intervals swallows every awakening. The case pins the corrected
  behaviour in both readers; the defect it was written to expose is fixed below.

- **A cross-frontend parity suite, so the two readers cannot drift apart
  silently.** `docs/DESIGN.md` §4.3 makes the read semantics a property of the
  file format rather than of any one reader: the phone and the web app must give
  the same answers for the same bytes, or the files stop being a single source
  of truth. Two independent implementations of a dozen subtle rules do not stay
  in agreement because everyone meant well.

  `test/fixtures/parity/` holds eight cases — a miniature `/Cairn/` folder, the
  questions to ask of it, and the answers both readers must give. `flutter test`
  runs them through the Dart reader and `nextcloud_app/dev test` runs the same
  files through the PHP one. **Both agreed on all eight on the first run**,
  which is the evidence the port was actually faithful rather than merely
  plausible. The cases are the divergence-prone rules: cumulative step snapshots
  resolving to the newest, source priority beating a later ingest, a superseded
  weight correction, all-or-nothing provenance, sleep segments deduplicating
  with the stage excluded from the key, the 60-minute episode gap either side of
  the boundary, and a shard full of malformed lines.

  The suite is built to fail rather than to pass. Both runners fail if they find
  no cases, because one that silently finds nothing reports all-clear while
  proving nothing; both fail on a query name they do not implement, so adding a
  query to a fixture forces the other frontend to implement it too. Verified by
  changing one golden to the naive sum a wrong reader would produce and watching
  both suites reject it, each quoting the case's own explanation of what a wrong
  reader does.

  Goldens are hand-written rather than generated from either reader. Generating
  them would record what the code currently does; the point is to record what it
  is supposed to do.

- **`TZ: Europe/Berlin` in `ci.yml`.** The parity fixtures are authored in a
  zone with daylight saving, because that is where the interesting failures
  live, and Dart reads its timezone from the environment rather than taking it
  as a parameter. This makes CI more deterministic, not less: the other 193
  tests were verified to pass identically under CEST, Europe/Berlin and
  Pacific/Kiritimati, so the only tests it affects are the ones that need it.
  Under a deliberately wrong zone exactly five tests fail, all of them parity
  cases. The suite also asserts the resulting UTC offsets on a winter and a
  summer date, which catches the subtler failure of two hosts carrying different
  `tzdata` — a name comparison would not.

- **`.forgejo/workflows/nextcloud-ci.yml`**, the quality gate for the subtree:
  the read-only guard, the `info.xml` schema check, and the unit and parity
  suites. Separate from `ci.yml` because it is a different toolchain with a
  different blast radius, and because Forgejo scopes concurrency groups per
  repository rather than per workflow, so it needs its own group name or it
  would cancel unrelated runs.

  It verifies the PHP toolchain rather than installing one: `setup-php`
  provisions through `sudo`/apt, and `docs/RELEASE.md` is explicit that this
  host must not expose a passwordless sudo grant reachable from CI. The step
  fails closed with the one-time host prep in its message.

  Its `paths:` filter is an optimisation, never a correctness dependency. A
  change to `lib/src/query/*.dart` that breaks parity does not touch
  `nextcloud_app/` and so would not start this workflow — but the shared goldens
  mean the always-on Flutter job catches it, which is the whole point of the
  fixtures being shared.

- **The seven dashboard queries, and the first real numbers off the files.**
  `HealthQueryService` owns what a caller should not have to know: how far back
  each question reads, and which resolution rule applies to what it finds. The
  windows are deliberately not uniform. `todayStepTotal()` returns `null` rather
  than `0` when nothing has synced, because "no data" and "you did not move" are
  different answers and only one is a measurement — while `dailySteps()`
  zero-fills, because there the number is a position on an axis and a missing
  day must keep its slot. `latestScalar()` walks backwards and stops at the
  first day with data instead of reading ninety days to answer "what do I
  weigh".

  `lastNNights(n)` reads **n + 2** dates where every other query reads `n`. A
  night is filed under the date it began and usually begins the evening before,
  so reading only today would find the tail of a night and report a sleep that
  started at midnight. The asymmetry is inherited from the mobile reader and
  reproduced deliberately; normalising it would look like a tidy-up and would
  make the two frontends disagree.

  The skeleton page now shows five figures computed by this layer from the
  actual shards. They were cross-checked against an independent implementation
  of the documented rules, run over a real 244-shard export: steps 60, last
  night 6 h 16 min, resting heart rate 72 bpm, three workouts — all four agree.
  That is evidence no unit test can give, because it exercises the rules against
  data nobody wrote to make them pass.

  `UserShardSource` is the only place below the controller that knows a user
  exists. The pure `ShardSource` contract has no notion of one, which is what
  keeps the read path runnable against a plain directory — and comparable with
  the mobile reader, which only ever has a single user.

- **The read-path semantics ported to PHP, as a server-free layer with 123
  tests.** `lib/Reading/` holds the rules from `DESIGN.md` §4.3 that every Cairn
  frontend must apply identically — strict JSON typing, timestamp handling,
  last-ingested-wins, source-priority dedup and sleep-episode aggregation — and
  imports no Nextcloud API at all. That is enforced by the read-only guard, not
  just intended: the rules stay testable without a server, which is also what
  will let them be compared against the mobile reader directly.

  The tests are written against the cases where a plausible port silently
  disagrees with the phone rather than against the happy path. Cumulative
  whole-day step snapshots resolve to the newest, never their sum. Source
  priority beats a later ingest, and ingest time breaks a tie only at equal
  priority — reversed, a phone's later sync would displace the wearable's better
  number. Provenance is all-or-nothing, so a `source_name` with no `modality`
  yields *no* source. Sleep-stage segments deduplicate on their window with the
  stage deliberately excluded from the key, so two sources disagreeing about the
  same minutes collapse to one segment instead of inventing an awakening. Total
  sleep is the union of asleep intervals, not their sum, because sources emit a
  whole-night `session` overlapping its own sub-stages.

  Three PHP-specific traps are closed and pinned by tests, because PHP's
  defaults are the opposite of the mobile reader's: lines decode to `stdClass`
  rather than associative arrays, since `json_decode(..., true)` makes `{}` and
  `[]` indistinguishable; numbers are checked with `is_int() || is_float()`
  rather than `is_numeric()`, which accepts the string `"62"`; and
  `is_main_sleep` is compared with `===`, because PHP evaluates `"true" == true`
  as true and would flip a night's main-sleep flag.

  Timestamp parsing is gated by a strict ISO-8601 pattern before PHP's date
  constructor sees it. Unguarded, that constructor is a natural-language parser
  — `now`, `+1 day`, a bare `62` all produce valid dates — so an unvalidated
  field would invent readings the phone never shows. Elapsed time is measured in
  integer milliseconds from timestamps; a night spanning the October fall-back
  is nine hours, not the eight the wall clock suggests.

  One inherited quirk is reproduced deliberately and documented: main sleep is
  decided per calendar date keyed on the episode's *onset*, so a morning nap
  after a night that began before midnight is flagged main for its own date.
  That is what the phone does with the same files, and "fixing" it here would
  make the two frontends disagree.

- **`nextcloud_app/dev refresh`, and the reason a dev instance needed it.**
  Nextcloud serves app assets with `Cache-Control: max-age=15778463, immutable`,
  which tells the browser never to revalidate them, and the only thing that
  varies the URL is a `?v=<md5(appVersion)>-<cachebuster>` suffix the server
  controls. Editing a stylesheet therefore changed nothing on screen until a
  hard reload, in every browser under test. `refresh` bumps the cachebuster, and
  `up` bumps it too so a restart always serves what is on disk. PHP and
  templates never needed it — they are read on every request.

  Setting the `debug` system config would drop the suffix entirely, which sounds
  like the fix and is the opposite of one: with no query string and an
  `immutable` header the browser has even less reason to look again.

  Fixing it turned up a second, larger problem. The image configures APCu as
  Nextcloud's local cache, and APCu memory is per-process: `occ` runs in the CLI
  process and updates the database and *its* cache, while the Apache worker goes
  on serving the value it cached earlier. Bumping the cachebuster took effect
  only intermittently — six rapid bumps produced three distinct URLs — and the
  same silent staleness applies to every `occ config:*` change, not just this
  one. `up` now switches APCu off, after which six rapid bumps produce six
  distinct URLs. That has to be done by emptying `config/apcu.config.php` *and*
  then deleting the key: `occ config:system:delete memcache.local` reports
  success while only editing `config.php`, the separate file re-supplies the
  value on the next request, and Nextcloud writes its whole merged config view
  back to `config.php` on any `set` — so each half alone leaves the value in
  place. Nextcloud now warns that no memory cache is configured; on a throwaway
  single-user container that is much the cheaper of the two problems.

  `up` also chowns `custom_apps` to the web-server user, and disables the
  first-run wizard. The first is a defect this compose file introduced:
  bind-mounting the app at `custom_apps/cairn` makes Docker create the parent
  directory itself, owned by root, before the image's entrypoint would have
  created and chowned it — so Nextcloud had an apps path it was told was
  writable and was not, and **Settings › Apps returned a 500 on every visit**.
  Confirmed unrelated to this app by reproducing it with Cairn disabled. It is
  worth fixing here precisely because the app still worked: the page it breaks
  is the one a contributor opens to check their app is listed, and it points the
  blame somewhere else entirely.

- **The app page renders on an opaque, centred sheet, and the header icon is
  white.** Three things were wrong once it was looked at in a browser rather
  than in `curl` output.

  Nextcloud's `#content` is transparent and shows the user's background image
  straight through, so the page's muted text — `--color-text-maxcontrast`, used
  for column headers and the explanatory note — was being read against a photo.
  Real apps avoid this by rendering into an opaque app-content area; this page
  now does the same with a single sheet on `--color-main-background`, which also
  fixes it for dark mode and for Theming's custom backgrounds. Verified under an
  emulated `prefers-color-scheme: dark`: the sheet turns near-black and the text
  inverts, because not one literal colour appears in the stylesheet.

  The sheet is centred rather than pinned to the left edge, and capped at
  1040px. At a 430px viewport it still fits, and the shard table scrolls inside
  its own box rather than making the page scroll sideways.

  The navigation icon was black on the blue header because it was authored with
  `fill="currentColor"` — which has nothing to inherit from when Nextcloud loads
  it through an `<img>`, so it resolves to black. Nextcloud applies no colour
  filter of its own (confirmed: `filter: none` on the icon of every app), and
  every first-party `img/app.svg` is authored white; `files/img/app.svg` is
  literally `fill="#fff"`. It is now white, with `img/app-dark.svg` added as the
  dark-on-light variant that 25 of the bundled apps also ship.

  The app *name* beside it was never actually bold: its computed `font-weight`
  is 500, identical to Files, Photos and Dashboard, because Nextcloud renders it
  from its own current-app button. What made it look heavier was the black icon
  next to white text; matching the icon resolved the appearance without
  touching the label.

- **The Nextcloud web app subtree (`nextcloud_app/`), with a development
  environment that needs only Docker.** `nextcloud_app/dev up` starts a pinned
  Nextcloud, waits out its first-run install, enables the app, loads health data
  and prints the URL. The app is bind-mounted from the working tree, so the edit
  loop is *edit a PHP file, reload the page* — no build step and nothing to copy.

  One container, not two: the app reads *files* and never touches the database,
  so SQLite costs nothing observable and removes a service, a healthcheck and a
  startup-ordering problem. It also makes `dev reset` honest — `down -v` really
  does return you to nothing, which matters because seeded health data lives in
  that volume.

  No Dockerfile, deliberately. The official Nextcloud image must start as root
  to fix permissions before dropping to `www-data`, which collides head-on with
  this repo's rule that every Dockerfile carries a `USER` instruction. Consuming
  the stock image from compose sidesteps that rather than making an exception to
  it; the pinning rule still binds and is honoured by tag *and* digest.

  The published port is bound to `127.0.0.1` explicitly. Compose's short port
  syntax defaults to `0.0.0.0`, which would have put a Nextcloud whose admin
  password is literally `admin` — and whose volume may hold a real health export
  — on every interface of the machine; `NEXTCLOUD_TRUSTED_DOMAINS` is no defence
  there, because a spoofed `Host` header satisfies it. Confirmed by checking that
  the instance answers on `localhost` and refuses the connection on the host's
  LAN address, with and without a spoofed header.

  `app:enable` is verified rather than trusted: it can report success while
  Nextcloud rejects the app for a version mismatch, so `up` re-reads `app:list`
  and fails loudly if the app is absent. Earlier revisions of `DEVELOPMENT.md`
  recommended `nextcloud-docker-dev`; that is a second repository to clone with
  its own conventions, wanting the app inside *its* workspace, which is the
  opposite of the one-command goal.

- **`tool/generate_dev_health_data.py`**, so a fresh clone comes up populated
  without anyone's real export. The only genuine `/Cairn/` folder is a person's
  health history and can never be committed, which would otherwise leave a
  first-time contributor with five blank screens and no way to tell a working
  reader from a broken one.

  It is not a random-noise generator. Each case where a plausible-looking reader
  silently disagrees with the mobile app about the same bytes is planted by its
  own named function, on a fixed date, with a printed explanation — cumulative
  whole-day step snapshots that must resolve to the newest rather than the sum,
  source priority outranking a *later* ingest timestamp, a superseded weight
  correction, provenance that is all-or-nothing (a `source_name` with no
  `modality` yields *no* source), sleep windows on both sides of the 60-minute
  episode gap, segments deduplicated with the stage deliberately excluded from
  the key, and seven kinds of malformed line. Output is deterministic for a
  given seed, verified by generating twice and diffing.

  The planted catalogue is the specification the PHP read-path port will be held
  to, which is why it exists before the port rather than after.

- **A read-only guarantee that is enforced rather than asserted.**
  `nextcloud_app/tests/read_only_guard.php` statically refuses any mutating
  filesystem call in `lib/`, any `fopen` in a mode other than read, and any
  `OCP\Files\*` import outside the two classes allowed to touch storage — so no
  writable handle can escape into code that might use it. It fails closed if it
  scanned zero files, because a guard reporting all-clear while checking nothing
  is worse than no guard; both behaviours were verified against a deliberately
  bad file and an empty tree. `tests/validate_info_xml.php` validates
  `appinfo/info.xml` against the app store's own schema and asserts the licence
  and the absence of any declared write surface. Both are plain PHP — no
  Composer, no PHPUnit, no server — so they run anywhere `php` does.

  Read-only is the app's whole contract (`DESIGN.md` §7): a second writer turns a
  folder of append-only shards into a folder of Nextcloud conflict copies. The
  dev container additionally mounts the app `:ro`, verified by watching a `touch`
  inside it fail.

  Two hardening details in the reader itself. Lines are read with a 64 KiB cap
  rather than an unbounded `fgets()`: "only the mobile app writes here" is a
  design intention, not an enforced boundary — the folder is ordinary Nextcloud
  storage the user can sync anything into — and one pathological line would
  otherwise buffer into memory on every page load. An over-long line is consumed
  without being held and counted once, not once per chunk; a planted 5 MB line
  renders in 0.2 s at 12 MB RSS. The cap is passed as `MAX_LINE_BYTES + 1`
  because `fgets($h, $n)` reads `$n - 1` bytes, so the constant means what it
  says; verified at exactly 65535, 65536 and 65537 bytes. And `readShard()`
  validates its own `$day` argument rather than trusting the caller: today it is
  only ever reached from a pattern-matched directory listing, but the method is
  one "show me this day" feature away from taking a request parameter, and a
  `../` in it would then walk out of the metric folder.

- **`.flake8`, aligning flake8 to black's 88 columns.** flake8 defaults to 79
  while black wraps at 88, so a black-formatted file could only satisfy both by
  accident — the existing `tool/*.py` pass only because they happen to stay
  under 79. Black is the canonical authority per `CLAUDE.md`, so flake8 is
  aligned to it rather than fought.

- **A CI workflow that fires on every branch push**
  (`.forgejo/workflows/ci.yml`). Until now `release.yml` was the only
  workflow and it fires solely on a `vX.Y.Z` tag, so the first automated
  feedback on a commit arrived while it was being released — with the signing
  keystore already decoded on disk. The new job runs the dependency-verification
  gate, `dart format`, `dart analyze` and `flutter test`, touches no secret and
  never writes `/build`, and uses a per-ref concurrency group rather than
  reusing the release group name — Forgejo scopes those per repository, so
  reusing it would queue every push behind every release. Tag pushes are
  excluded twice over: by the `branches:` filter and by an explicit job-level
  `if:`, because Forgejo's filter semantics have diverged from GitHub's before
  and the cost of being wrong is this job racing a release.

  Two things it does that the release job did not. `dart analyze` runs with
  `--fatal-infos --fatal-warnings`: bare `dart analyze` exits 0 on info-severity
  diagnostics and most `very_good_analysis` rules are info-severity, so
  "CI treats lints as errors" was not actually enforced anywhere. And the
  Flutter version is read out of `release.yml` rather than duplicated, using the
  same two expressions the F-Droid recipe greps — so CI doubles as a canary for
  that parser.

- **`tool/check_dependency_verification.py`**, the half of dependency
  verification Gradle cannot do for itself. Gradle proves the pinned hashes
  match the bytes a repository served; it cannot prove verification is switched
  on. A single `org.gradle.dependency.verification=off` line in a *tracked*
  `gradle.properties` disables the entire mechanism while builds still print
  BUILD SUCCESSFUL and `verification-metadata.xml` still looks pristine —
  confirmed by building an APK from a deliberately corrupted pin. The script
  rejects that property, plus a relaxed `<verify-metadata>`, blanket-trust
  elements, artifacts with no checksum, duplicate entries Gradle would silently
  merge, and coverage dropping below a floor. CI additionally forces
  `-Dorg.gradle.dependency.verification=strict`, so the two controls cover each
  other. Given a base revision it also flags a checksum that moved under an
  unchanged coordinate — published artifacts are immutable, so that is never
  routine — and a pin removed with no replacement version. The base comparison
  is fail-closed: a named-but-unreadable base exits non-zero rather than
  printing an all-clear.

- **Gradle dependency verification.** `android/gradle/verification-metadata.xml`
  pins a SHA-256 for every Maven artifact the Android build resolves — ~900
  components, covering the app's dependencies, Flutter's engine artifacts and
  the buildscript classpath (AGP, the Kotlin plugin). A substituted or
  unexpected artifact now fails the build instead of being consumed silently.
  Verified by tampering with one checksum and confirming the build fails with
  the artifact and repository named, and by building inside F-Droid's own
  buildserver image against a freshly installed SDK. `docs/RELEASE.md` §2a-deps
  documents when and how to regenerate it.

  The `aapt2` entries for macOS and Windows are added by hand, because Gradle
  records only the classifier of the host that generated the file. Left as
  generated, the file is Linux-only and a contributor on another OS hits a
  verification failure on their first `flutter run`, naming `aapt2` with no hint
  that their OS is the cause. The `linux` hash was downloaded the same way and
  matched the one Gradle generated by itself, which is what establishes that the
  manual download path returns the same bytes as Gradle's own resolution.

- **The Gradle wrapper distribution is checksum-pinned.**
  `android/gradle/wrapper/gradle-wrapper.properties` now sets
  `distributionSha256Sum`. That distribution is what *interprets* the
  verification metadata above, and it was being fetched on nothing but TLS — a
  substituted distribution would not have to defeat checksum pinning, it could
  just decline to honour it. The value was cross-checked against Gradle's
  published `.sha256` and the copy already on disk, and confirmed to enforce: a
  deliberately wrong sum makes the wrapper refuse to run.

### Changed

- **`minSdkVersion` is now 34 (Android 14).** Health Connect is part of the
  platform only from Android 14; on Android 8-13 it is Google's separate Play
  Store app, so a Play-less device could install Cairn and then find nothing to
  read — the app declared support it could not deliver. Requiring 14 makes the
  promise true on every device that can install it, and keeps the F-Droid build
  free of a non-free dependency. The cost is real and deliberate: Android 8-13
  devices that *do* have Health Connect can no longer install Cairn.

  The store descriptions state the requirement in both languages, and the
  in-app setup guide no longer tells Android 8-13 users to fetch Health Connect
  from the Play Store — on a supported device there is nothing to install.

- **The app store now publishes a project contact, not a personal one.**
  `info.xml` carried a personal address, and the app store shows it to every
  self-hoster who installs the app. Releases come from the `LuminaAppsDev`
  account — which is already what `<bugs>` and `<repository>` point at, and what
  F-Droid lists for the mobile app — so the contact is `luminaapps@gmail.com`
  in both `info.xml` and `composer.json`. The author name is unchanged and still
  matches the F-Droid listing, so the two channels name one maintainer.

  `tests/validate_info_xml.php` now asserts the contact and that `<bugs>` and
  `<repository>` point at the project's own repository. This failure is silent
  and permanent — an address published in a release cannot be recalled from the
  installs that already carry it — so it is checked rather than remembered.
  Verified by putting the personal address and a fork URL back and watching each
  be refused.

  `docs/RELEASE.md` §6 also records which account opens the signing-certificate
  request: ownership is verified against that account's public email, so it has
  to be the same one.

- **`docs/DEVELOPMENT.md` §5 gives the right reason for the AGPL subtree.** It
  claimed the licence was an app-store requirement. It is not: the store's
  `info.xsd` enumerates `MIT`, `Apache-2.0`, `BSD-*`, `MPL-2.0` and others, and
  apps ship under those today. The plugin-linking question does not force it
  either — that is unsettled, MIT is GPL-compatible regardless, and Cairn never
  redistributes Nextcloud.

  What actually binds is the frontend the app bundles: `@nextcloud/vue` and
  `@nextcloud/vite-config` are AGPL-3.0-or-later, and `@nextcloud/router`,
  `/l10n` and `/initial-state` are GPL-3.0-or-later, all compiled into the `js/`
  bundle that ships — ordinary distribution of a combined work, no linking
  theory required. The conclusion is unchanged and `info.xml` carries
  `AGPL-3.0-or-later` (the SPDX form, valid since the schema's `min-version` 31,
  rather than the deprecated `agpl`). The corollary is now written down: an MIT
  web app is possible, but only by avoiding every `@nextcloud/*` package, and
  that has to be decided before the frontend is written.

- **The pre-commit hook refuses personal health data, not only signing secrets.**
  It now rejects anything staged under `nextcloud_app/dev-data/`,
  `nextcloud_app/docker/.env`, or any `.jsonl` outside `test/fixtures/` — the
  export's actual payload, and the realistic way a stray shard copied "just to
  look at" would leak. Both paths are gitignored already; the hook is the layer
  that survives `git add -f`. A leaked signing key can be rotated; a leaked
  health history cannot.

  It also reads the staged list as `git -c core.quotePath=false diff --cached
  --name-only -z`, which is load-bearing rather than tidiness. With Git's
  defaults, a path containing any non-ASCII byte, a backslash or a quote arrives
  C-escaped and wrapped in double quotes — `édata.jsonl` comes through as
  `"\303\251data.jsonl"`. Both guards anchor their patterns at each end, so the
  added quotes defeat them simultaneously and the file sails through. Confirmed
  by staging exactly that filename against the previous version and watching it
  pass; it is now caught. NUL delimiting additionally stops a path containing a
  newline from being read as two paths.

- **Simplified the F-Droid recipe's build steps** at the fdroiddata reviewer's
  request: the Flutter SDK goes on `PATH` instead of being referenced through a
  `FLUTTER_BIN` variable, the conditional `mv` guard became a plain
  `rm -rf /build/cairn` followed by `mv`, and `pushd`/`popd` no longer discard
  their output. The `rm -rf` is kept deliberately — it is not a check, and
  without it a leftover `/build/cairn` makes `mv` nest the tree inside it and
  build the wrong source.

  The commit assertion on the Flutter SDK was dropped too. It read
  `FLUTTER_COMMIT` from the release workflow and failed closed if the checked-out
  tag did not resolve to it. Conceding it is cheap: the identical assertion still
  runs in `release.yml`, which is the side that holds the signing key, and on
  F-Droid's side a moved tag still fails closed because the rebuild stops
  matching the reference binary. Only the diagnosis is lost.

  Verified with a full `fdroid build --test --on-server` inside
  `registry.gitlab.com/fdroid/fdroidserver:buildserver`: the rebuild of the
  pinned commit reports "...successfully verified" against the published
  reference APK, and the file remains in canonical `rewritemeta` form. The
  fail-closed backstop the concession relies on was tested too — pointing a
  block's `binary:` at the wrong ABI's APK ends the build with "compared built
  binary to supplied reference binary but failed" and a non-zero exit.

- **`repositoriesMode` is deliberately not set** — it would be the obvious way
  to stop a third-party plugin introducing a repository of its own, but it is
  not usable here. `FAIL_ON_PROJECT_REPOS` cannot be used at all: every Flutter
  plugin — and Flutter's own Gradle plugin — declares
  `rootProject.allprojects { repositories { … } }`, so the strict mode fails
  while applying `dev.flutter.flutter-gradle-plugin`. `PREFER_SETTINGS` applies
  but silently drops Flutter's engine repository, making every `io.flutter:*`
  artifact unresolvable unless we replicate Flutter's internal URL derivation in
  our own settings file. Checksum pinning gives the same guarantee without that
  coupling, and also covers the buildscript classpath, which `repositoriesMode`
  does not.

- **The build-id suppression uses AGP's current DSL type.** `android/build.gradle.kts`
  looked the Android library extension up as `com.android.build.gradle.LibraryExtension`.
  AGP 9 deprecates that class — *"will be removed in AGP 10.0"* — and stops
  registering it as the public extension whenever `android.newDsl=true`, which
  is AGP 9's own default; the only reason the lookup still resolved is that
  Flutter's template pins `android.newDsl=false`. Verified in an isolated
  project that under `newDsl=true` the old lookup fails outright
  (`Extension of type 'LibraryExtension' does not exist`) while
  `com.android.build.api.dsl.LibraryExtension` resolves under both settings.
  A clean native rebuild confirms `-Wl,--build-id=none` still reaches CMake and
  `libdartjni.so` still carries no build-id note, so reproducibility is
  unaffected.

- **The F-Droid recipe is now comment-free and kept in canonical
  `rewritemeta` form**, with everything it used to explain moved into
  `docs/RELEASE.md` §2a-recipe. fdroiddata's CI runs `fdroid rewritemeta` and
  fails the merge request on any diff, and that tool strips comments — so a
  documented copy could never survive the round trip. The repo copy and the
  submitted copy are now the same file, with no regeneration step to forget.

- **Documented how to regenerate that canonical form against CI's toolchain.**
  The formatting depends on the *ruamel.yaml* version, not on fdroidserver:
  ruamel 0.18.10 (Debian trixie, which fdroiddata's CI runs) folds a long plain
  scalar onto the following line, while 0.17.x does not fold it at any width. A
  file canonicalised locally against 0.17.x therefore fails CI with a
  whitespace-only diff that gives no hint of the cause. `docs/RELEASE.md`
  §2a-repro now pins the reproduction procedure, including that CI fetches
  fdroidserver from git master rather than using the Debian package.

### Fixed

- **Refresh and sync never finished on a device without Health Connect.** The
  `health` plugin signals a missing Health Connect with an `UnsupportedError` —
  an `Error`, not an `Exception` — so the `on Exception` catch in
  `CairnServices._runRefresh` did not see it and the refresh future completed
  with an error instead of a result. Every caller awaits that future before
  clearing its own flag, so the Home spinner turned forever and Settings sat on
  "Syncing…" with Connect, Disconnect and Sync now all disabled until the
  process was restarted. Reported from an Android 13 device, where Health
  Connect was absent.

  Three changes, because one alone would only have moved the failure: the
  repository asks whether the store is available and raises a typed
  `HealthStoreUnavailableException` before the plugin can throw its `Error`; the
  refresh catches `Object` rather than `Exception`, so nothing at all escapes
  it; and Home and Settings clear their busy flag in a `finally`, so a future
  escape disables no buttons. A new `RefreshStatus.healthUnavailable` carries
  the case to the UI, which now says Health Connect is unavailable instead of
  showing a generic read error — or nothing.

  A failed `configure()` is also no longer cached. It was stored in
  `_configuring` and re-awaited by every later call, so a device that gained
  Health Connect after the first attempt could never pick it up without a
  restart.

  Catching `Object` has a cost, though: a genuine bug — a `TypeError`, a failed
  assertion — lands in the same bucket as an expected failure and is shown to
  the user as a benign "could not read", leaving nothing behind but a
  `debugPrint`. So `reportIfBug` now sorts the two: an `Exception` is an
  expected outcome and passes quietly, anything else is handed to Flutter's
  error machinery, where uncaught errors already go. It is reported rather than
  rethrown, so the user still gets their message and the bug still surfaces.

- **Nextcloud errors stayed English in the German UI.** Connect and sync
  failures rendered the exception's own message — "Login Flow v2 init failed",
  "network error: …" — which is written for a log, not for a user, and was the
  one part of an otherwise fully translated interface that never switched
  language. `NextcloudSyncException` now carries a `SyncErrorKind` alongside the
  English text, and the UI translates the kind: the message keeps serving logs
  and bug reports, and nothing server-facing reaches the screen. Where the
  server gave an HTTP status it is appended, since a number is language-neutral
  and is the most useful thing to quote when asking for help; 401 and 403 are
  recognised as an expired app password rather than reported as a bare status.

- **`wait_for_install` reported timeouts into `/dev/null`.** It ended in `die`,
  and every caller runs it inside a conditional with output suppressed — so a
  Nextcloud that never came up exited the script silently, its own explanation
  discarded. It now returns non-zero and lets each caller decide; `up` still
  dies with the same message. Found because the first `verify-package` run
  failed with no output at all.

- **The per-stage sleep breakdown double-counted the same minutes.** Time per
  stage was a plain tally, so a whole-night `session` was added to the
  light/deep/rem segments describing those very minutes — the parts summed to
  more than the night. Nothing rendered them as durations yet, so it was latent
  rather than visible, which is exactly the state in which a wrong number waits
  for the first chart to show it.

  The breakdown is now a **partition**: every instant is attributed to exactly
  one stage, each claiming only time no more specific stage has claimed, in the
  order `awake`, `out_of_bed`, `deep`, `rem`, `light`, `asleep_unspecified`,
  `session`, `in_bed`. Wakefulness comes first deliberately, so the breakdown
  cannot contradict the total.

  Two invariants follow, and both are asserted in each reader's tests and in the
  shared fixtures: the asleep stages sum to **exactly** the night's total sleep,
  and every stage together sums to the time the source actually described.
  Checked against a real export — 5 h 30 min of stages against 5 h 30 min of
  total, on each of three nights. `session` now means what it honestly is,
  asleep with the stage unrecorded, and on a source that describes every minute
  it claims nothing at all: it disappeared from all three real nights.

  `perStageMs` joined the parity encoding at the same time, so the breakdown is
  a cross-frontend contract rather than something each reader decides for
  itself. `DESIGN.md` §4.3 states the rule.

- **Sleep totals counted time you were awake.** A night's time asleep was the
  union of asleep-stage intervals. Samsung Health emits a whole-night `session`
  segment alongside the fine-grained stages, `session` counts as asleep, and
  that one segment spans the awake stretches inside it — so a real night with
  **26 awakenings** reported 6 h 16 min asleep at **100 % efficiency**. Across
  five nights of a real export, every efficiency figure was 100 %.

  Time asleep is now the union of sleep intervals **minus** the union of wake
  intervals: a set difference, not a heuristic about which stages to ignore, so
  it needs no special case for sources that emit a session marker and none for
  sources that do not. The same night now reads 5 h 30 min at 88 %, and the five
  nights read 86–98 %, tracking their awakening counts. Two independent
  corrections — subtracting the wake union, and ignoring `session` where finer
  stages exist — agreed on the answer before either was written, which is what
  gave confidence it was right.

  `in_bed` is deliberately **not** treated as wakefulness: some sources emit it
  across the entire time in bed, and subtracting it would zero out the night.
  Being in bed is compatible with being asleep; `awake` and `out_of_bed` are not.

  Both readers had the bug identically, so it was a defect in the read semantics
  (`DESIGN.md` §4.3, now amended) rather than in either port — the shipped phone
  app was showing the same wrong number. Fixed in the Flutter and PHP readers in
  the same commit, with the shared golden updated alongside; the only test that
  failed on either side was the parity case that had pinned the old behaviour.

- **The Nextcloud sleep view can step through nights,** as the phone app's can.
  Both buttons carry a word as well as an arrow, because the list runs newest
  first and an arrow alone leaves the direction ambiguous. The heading shows the
  onset date and the time range, which is what tells apart two nights filed under
  the same date — a sleep beginning before midnight is filed under the day it
  started, so an evening onset and the next night's early one share one.

- **An edited PHP file kept serving its previous version for up to a minute.**
  The Nextcloud image ships `opcache.revalidate_freq=60`, which is right for a
  server and wrong for a working tree mounted live — and it made this
  repository's own documentation false, since `dev up`'s output and both READMEs
  claimed PHP changes need no step. `up` now mounts a small dev php.ini setting
  it to 0, so a change is picked up on the next request. Found while debugging a
  500 that had already been fixed in the file being served.

- **`Settings › Apps` returned a 500 on every visit.** Bind-mounting the app at
  `custom_apps/cairn` makes Docker create the parent directory itself, owned by
  root, before the image's entrypoint would have created and chowned it — so
  Nextcloud had an apps path it was told was writable and was not. Confirmed
  unrelated to this app by reproducing it with Cairn disabled. Worth fixing
  precisely because the app still worked: the page it breaks is the one a
  contributor opens to check their app is listed, and it points the blame
  elsewhere.

- **The shared Flutter SDK install is now atomic** in both workflows. Each
  cloned straight into `$HOME/flutter-$VERSION`, guarded only by a check that
  `bin/flutter` was executable. A run killed mid-clone left that path
  half-populated, and `git clone` refuses to write into a non-empty directory —
  so every later run of *both* workflows would keep failing until someone
  deleted it by hand. Harmless while only tag pushes built; the new CI job's
  `cancel-in-progress` makes it reachable. Both now stage the clone and `mv` it
  into place, keeping a rival job's tree if it published first.

- **The release job no longer mistakes an API outage for "no release exists".**
  Both publish steps looked up the release by tag with `curl -sS` and then
  decided from `jq`: no `.id` in the response meant "create it". A 404 body and
  a 502/503 body both lack an `.id`, so a transient upstream error took the
  create branch — publishing a second release for a tag that already had one, or
  failing later in a way that pointed at the wrong cause. The lookup now reads
  the HTTP status explicitly and branches on it: 200 uses the id (and treats a
  200 without one as an error), 404 creates, anything else fails the job with
  the status and response body. The GET is retried a few times first, which is
  safe precisely because it is a GET — no retry was added to the POSTs. A
  transport failure (DNS, connection refused) now reports the same way instead
  of falling out of curl's own message, and a 200 carrying malformed JSON is
  reported rather than dying inside `jq`.

- **Error bodies are capped and scrubbed before reaching the job log.** The new
  failure paths print the API's response to help diagnose an outage. Some
  proxies and debug-mode servers echo the request's own headers back in the
  body, so that response can contain the `Authorization` header — it is now
  truncated and passed through a redacting `sed` first.

- **Temp-file traps are installed before the next file is created.** Both
  publish steps create two `mktemp` files; with a single `trap` registered after
  both, a failing second `mktemp` aborts the step under `set -e` before the trap
  exists, orphaning the first file.

### Security

- **The pre-commit hook refused Android signing material but not the Nextcloud
  app's private key.** App-store releases are signed with an OpenSSL keypair
  conventionally kept at `~/.nextcloud/certificates/cairn.key`, and a copy left
  in the working tree would have been committable. `*.key`, `*.pem` and `*.p8`
  are now refused alongside the keystores. `.crt` is deliberately still allowed:
  the counter-signed certificate is public and belongs in the repository, while
  the key beside it never does. Found by testing the hook against the file the
  new packaging step is about to make people create, rather than after somebody
  created one.

## 0.2.3 — 2026-08-19

Packaging fix. The 0.2.2 binaries could not be verified by F-Droid — its scanner
rejected them — so reproducible builds never actually took effect. No app
behaviour change.

### Fixed

- **Disabled AGP's dependency-metadata signing block.** The Android Gradle
  Plugin embeds a ~5 KB payload, encrypted for Google Play, into the APK signing
  block by default. F-Droid cannot inspect it and rejects any APK carrying it
  ("Found extra signing block 'Dependency metadata'"), which failed the
  reference binary for all three ABIs. `android/app/build.gradle.kts` now sets
  `dependenciesInfo { includeInApk = false; includeInBundle = false }`.

  Worth recording why this was not caught before tagging 0.2.2: the block lives
  in the APK *signing* block, between the zip entries and the central directory,
  so an entry-by-entry comparison of two APKs reports them as identical while
  both carry it. Local verification now inspects the signing-block ID list too.

### Changed

- **Per-ABI downloads are named by ABI, not by versionCode.**
  `cairn-vX.Y.Z-arm64-v8a.apk` rather than `cairn-vX.Y.Z-82.apk`, so the
  filename says which file a device needs. This is possible because the recipe
  now gives each build block its own `binary:` URL instead of sharing one
  app-level `Binaries:` template — a shared template can only substitute `%v`
  and `%c`, never the ABI, which is what forced version-code names in 0.2.2.
  The version codes are unchanged in meaning (`base × 10 + {1,2,3}`) and are
  still declared per block in the recipe.

## 0.2.2 — 2026-08-19

Packaging release enabling **reproducible builds** on F-Droid. F-Droid now
rebuilds the app and verifies it byte-for-byte against the APKs published here,
then distributes our signature rather than its own — so the F-Droid download and
the direct download are interchangeable and users can switch between them
without reinstalling. No app behaviour change.

### Changed

- **Release builds now compile at a pinned absolute path** (`/build/cairn`).
  Dart's AOT compiler embeds the Flutter project root into `libapp.so`
  (flutter/flutter#165111), so a release APK contains the literal build path.
  F-Droid's rebuild has to compile at the same path or verification can never
  succeed; CI stages the checkout there and the fdroiddata recipe moves its
  checkout onto the same path. `PUB_CACHE` is pinned inside that tree too, so
  package paths match and the release job no longer mutates the runner's shared
  pub cache.

- **The release publishes one APK per ABI alongside the universal APK.**
  `cairn-vX.Y.Z-<versionCode>.apk` for armeabi-v7a, arm64-v8a and x86_64 (codes
  `base × 10 + {1,2,3}`) are what F-Droid verifies against; the universal
  `cairn-vX.Y.Z.apk` stays for direct download. Per-ABI filenames encode the
  versionCode because F-Droid's `Binaries:` template supports only `%v` and
  `%c` — there is no ABI placeholder.

### Fixed

- **Dropped the GNU build-id from natively-compiled plugin libraries.** The
  Android NDK sits at a different absolute path on our runner than on F-Droid's
  buildserver. That path lands in the debug info of `package:jni`'s
  `libdartjni.so`; the linker hashes the unstripped object into a build-id note,
  and stripping then discards the debug info but leaves the differing hash — so
  two byte-identical libraries differed by exactly those 20 bytes and would have
  failed verification. `android/build.gradle.kts` now passes
  `-Wl,--build-id=none` to CMake for library subprojects. Verified: all three
  per-ABI APKs are byte-identical to builds made in F-Droid's buildserver image.

- **Signing material is written with `umask 077` and the staged build tree is
  removed on job exit.** The release runner is bare metal and its disk is not
  discarded between jobs, so the decoded keystore and `key.properties` are no
  longer left world-readable, and the staging directory that holds them is wiped
  even when the job fails.

## 0.2.1 — 2026-07-27

Packaging release for F-Droid — ships one APK per ABI (smaller downloads).
No app behaviour change.

### Changed

- **F-Droid ABI split.** The Android build now gives each per-ABI APK a
  distinct versionCode (`base × 10 + abiIndex`, ordered armeabi-v7a < arm64-v8a
  < x86_64), the scheme F-Droid's Flutter packaging expects (requested by the
  F-Droid maintainer). It's a no-op for the universal APK our own CI publishes
  to GitHub/Forgejo — that output has no ABI filter, so those releases keep the
  plain pubspec versionCode. The fdroiddata recipe builds `--split-per-abi` and
  mirrors the scheme via `VercodeOperation`.

## 0.2.0 — 2026-07-01

First feature release since the 0.1.x F-Droid-enabling patches. Highlights:
browse and compare past nights in the Sleep screen (header arrows or tap the
trend chart), a colour-coded hypnogram with tap tooltips, and a "last synced"
time in Settings — plus fixes that make the data correct on real devices: iOS
HealthKit now prompts and reads, edited/corrected readings update on the
dashboard, and Samsung Health step totals are right (with on-ingest compaction
keeping the files tidy).

### Added

- **Browse past nights in the Sleep screen.** The deep-dive was fixed to last
  night; a prev/next control in the header now steps through the loaded nights
  (the same seven the trend chart already covers), re-pointing the hypnogram,
  stage breakdown and headline numbers at the selected night. No extra query —
  those nights were already loaded. A data refresh returns to the latest night.
  You can also **tap a night's column in the trend chart** to jump straight to
  it; the selected night's bar is highlighted and the rest are dimmed.

- **"Last synced" time in Settings.** The Nextcloud card now shows when this
  device last completed a sync (or "Not synced yet"), persisted device-locally
  in the sync journal so it survives restarts. The instant is stamped only on a
  clean push — a failed upload never reports a false "synced" time — and a
  no-op run where everything was already up to date still counts.

### Fixed

- **Today's step total was stuck at a stale value with Samsung Health** (and
  any source that re-reports a cumulative daily total). Samsung Health exposes
  the day's steps as one whole-day record whose value grows through the day, so
  each refresh appends a fresh snapshot with the identical `(start,end)` window.
  The read path collapsed same-window records but kept the *first* one — the
  earliest, stalest snapshot (e.g. 14 while the watch showed 7050). It now
  breaks same-window ties by the ingest timestamp (`creation_date_time`), so the
  newest snapshot wins — the same last-ingested-wins rule already used for
  scalar corrections. Genuine per-interval step deltas keep distinct windows and
  are still summed (DESIGN.md §4.3).

- **Corrected health entries now reflect in the dashboard.** When a reading is
  edited in the source health app (e.g. a mistyped manual weight is fixed), the
  corrected value is re-read on the next sync and appended (append-only forbids
  rewriting the original), but the read path previously showed whichever of the
  two same-timestamp readings sorted first — often the stale one. The query
  layer now resolves readings that share a source and effective instant by
  **last-ingested-wins** (the OMH header's `creation_date_time`), so the
  correction supersedes the stale value on the dashboard without any file
  rewrite. Applies to weight and heart-rate read paths. Value corrections at an
  unchanged timestamp are covered; timestamp edits and deletions still await the
  Phase 8 change-token work. Documented as a shared read-rule both frontends
  must apply (DESIGN.md §4.3).

- **iOS HealthKit access never prompted** (found testing on an iPhone
  simulator): the app showed no Health permission sheet and was absent from
  Settings → Privacy → Health, because the HealthKit entitlement/capability
  was never wired into the Xcode project — iOS silently drops the
  authorisation request without it. Added `ios/Runner/Runner.entitlements`
  (`com.apple.developer.healthkit`, read-only — no write/clinical scope) and
  set `CODE_SIGN_ENTITLEMENTS` on the three app-target build configs. The Dart
  request path and `NSHealthShareUsageDescription` were already correct.

### Changed

- **Ingest compacts re-reported cumulative totals instead of piling them up.**
  A source that re-reports a running total in a fixed window (Samsung Health's
  whole-day step record) previously appended a fresh snapshot on every refresh,
  bloating the day's shard with near-duplicate lines. Ingest now recognises a
  **supersession** — a re-read whose value changed but whose schema + source +
  time-frame match a line already on disk — and compacts the shard (drops the
  stale line, rewrites atomically) so each `(source, window)` keeps a single
  current record. This is the one sanctioned exception to append-only; it fires
  only on an actual supersession (a plain append otherwise) and is deterministic
  so multiple devices converge. Pre-existing snapshot pile-ups collapse on the
  next refresh that brings a new value. To protect the "files are the source of
  truth" invariant, compaction **refuses to rewrite a shard that holds an
  unparseable line** (a torn append from a crash), falling back to a plain
  append so such a line is never silently dropped (DESIGN.md §4.3, §5.3).

- **Redesigned the sleep-stage hypnogram.** The "Stages through the night"
  chart was a single-colour stepped line whose vertical transitions through the
  middle "Light" band made the night look noisy and left every phase the same
  colour. It now draws one coloured bar per stage segment — colours matching the
  "Where the night went" donut — so deep / light / REM / awake stand apart at a
  glance. Tapping a bar shows that phase and the clock time it spanned.

- **Pinned the iOS deployment target to 14.0 in source** so it no longer needs
  a manual Xcode bump on each checkout. Set `IPHONEOS_DEPLOYMENT_TARGET` (the
  project-level configs), `MinimumOSVersion` in `Flutter/AppFrameworkInfo.plist`,
  and added a committed `ios/Podfile` (`platform :ios, '14.0'` plus a
  `post_install` hook that enforces 14.0 on every pod, so a pod with a lower
  declared target can't drag the floor back down).

## 0.1.3 — 2026-06-23

Patch release: makes the source build cleanly on F-Droid's build server.
No functional or behavioral changes to the app.

### Fixed

- **F-Droid build compatibility** (found by test-building the recipe with
  `fdroid build`):
  - The recipe's `rm:` listed platform dirs (`linux`/`macos`/`web`/`windows`)
    that don't exist in this Android+iOS project; F-Droid aborts when an `rm:`
    glob matches nothing. Trimmed to `ios`.
  - F-Droid strips signing configs from `build.gradle.kts` (it signs with its
    own key), and its line-based scrubber mangled the multi-line
    `signingConfig = … ?: …` expression into invalid Kotlin. Rewrote the
    release signing as two single-statement assignments — a debug default,
    overridden when `android/key.properties` exists — which the scrubber
    removes cleanly. Locally- and CI-signed builds behave exactly as before.

## 0.1.2 — 2026-06-23

Patch release: fixes a crash on launch in release builds and adds store
screenshots. The 0.1.1 binaries were withdrawn (see below).

### Fixed

- **Release builds crashed on launch** with `NoSuchMethodException:
  androidx.work.impl.WorkDatabase_Impl.<init>`. Flutter enables R8 for release
  builds, and R8 "full mode" stripped the no-arg constructor of WorkManager's
  Room database, which Room instantiates by reflection. Added
  `android/app/proguard-rules.pro` (auto-included by the Flutter Gradle plugin)
  that keeps Room database constructors. Debug builds were unaffected, so it
  surfaced only in the published APK.

### Added

- **Store screenshots** — six per locale (English + German) under
  `fastlane/metadata/android/<locale>/images/phoneScreenshots/`, captured from
  a release build.

### Changed

- Advanced the F-Droid recipe seed to the `v0.1.2` tag / versionCode 3 (the
  first launchable release) and added the matching `changelogs/3.txt`.
- Added a "smoke-test the signed release build on a device" item to the
  RELEASE.md pre-release checklist, so a release-only crash can't ship again.

## 0.1.1 — 2026-06-23

> **Withdrawn** — the release binaries crashed on launch under R8; superseded
> by 0.1.2. The source changes below still stand.

Moved the project under the **LuminaApps** identity and prepared the F-Droid
listing graphics. No functional changes to health reading, the OMH format, or
sync.

### Changed

- **Application identity → `com.luminaapps.cairn`.** Renamed the Android
  `applicationId`/namespace, the iOS bundle identifiers, and the background-sync
  task identifier from `io.github.theflipside.cairn` to the reverse-domain of
  `luminaapps.com` (a domain the project controls). This is a **new package
  identity**: a 0.1.0 sideload install does not upgrade in place — uninstall and
  reinstall (the local cache rebuilds from your Nextcloud; OS health permissions
  are re-granted). The fdroiddata recipe is renamed to
  `fdroid/com.luminaapps.cairn.yml` and its seed build is anchored to the
  `v0.1.1` tag, since the `v0.1.0` APK still carries the old id.
- **Public repository → `github.com/LuminaAppsDev/cairn`.** Updated the F-Droid
  recipe URLs, the release workflow's `GH_REPO`, and the docs clone URL.
- **Privacy policy published.** `docs/PRIVACY.md` now points at the canonical
  published copy at <https://luminaapps.com/cairn-privacy.html> (dated
  2026-06-23) with the repository URL filled in.

### Added

- **F-Droid listing graphics.** A generated 1024×500 `featureGraphic.png` per
  locale, `images/phoneScreenshots/` directories for the (manually captured)
  screenshots, a feature-graphic generator at
  `tool/generate_feature_graphic.py`, and `fastlane/metadata/README.md`
  documenting the layout and screenshot specs.

### Fixed

- **Home screen could fail with "Couldn't load this data" on a device with no
  synced data yet** (e.g. a fresh install). Reconciling an empty set of sleep
  readings returned a `const` list that the query layer then sorted in place,
  throwing "Cannot modify an unmodifiable list". It now returns a mutable empty
  list, with a regression test covering the empty-store path.

## 0.1.0 — 2026-06-17

First release. Reads Apple Health / Android Health Connect, normalizes to Open
mHealth / IEEE 1752.1 JSON-Lines files, and syncs them to the user's own
Nextcloud; in-app dashboard with a sleep deep-dive, BMI and per-category
screens; English + German; opportunistic background sync; F-Droid / sideload
packaging and a dual-publish (GitHub + Forgejo) release pipeline.

### Added

- **`docs/RELEASE.md` — per-channel release guide (Phase 6).** Step-by-step
  distribution instructions for F-Droid (official repo + self-hosted, including
  the Flutter build recipe), sideload/direct APK, Google Play (with the Health
  apps declaration and the cross-platform-sync policy tension), the Apple App
  Store (HealthKit review rules), and the Nextcloud App Store (signing +
  publishing). Includes a dedicated routine for keeping the Nextcloud app
  current across Nextcloud major releases. Cross-linked from DESIGN.md §10.3
  and §15.
- **F-Droid packaging + APK release CI (Phase 6).** F-Droid listing metadata
  under `fastlane/metadata/android/` (English + German; store title
  "Cairn: Health Aggregator", launcher label stays "Cairn"), a ready-to-submit
  fdroiddata build recipe at `fdroid/io.github.theflipside.cairn.yml` (Flutter
  `srclib` build, pinned to the CI Flutter version), and a Forgejo Actions
  workflow `.forgejo/workflows/release.yml` that, on a `vX.Y.Z` tag, runs on the
  self-hosted bare-metal `linux` runner, analyzes/tests, builds + signs the
  release APK, and publishes it (with a SHA-256 checksum) as both a **GitHub
  Release** (`GH_RELEASE_TOKEN`) and a **Forgejo release** (`RELEASE_TOKEN`).
  Actions are full-URL + SHA-pinned. RELEASE.md documents the required CI
  secrets and that F-Droid builds its own copy server-side.
- **`docs/PRIVACY.md` — drafted privacy policy (Phase 6).** Reflects Cairn's
  "the developer collects and stores nothing" model: health data is read-only,
  lives only on-device and in the user's own Nextcloud (never iCloud or any
  developer/third-party cloud), no advertising/analytics/trackers, HTTPS-only,
  app-token in OS secure storage, with clear data-deletion steps. Written to
  satisfy the Apple/Google privacy-policy requirements; contact + published-URL
  placeholders to fill before release.

- **Opportunistic background sync (Phase 5, §4.4).** A periodic task (every
  ~6 h, network-required, not on low battery) reads the health store and
  uploads to Nextcloud while the app is closed, via `workmanager` (Android
  `WorkManager` + iOS `BGAppRefreshTask`), reusing the same single refresh cycle
  as the foreground so they can't diverge. It is best-effort — the OS decides
  actual timing and correctness never depends on it. Android declares
  `health.READ_HEALTH_DATA_IN_BACKGROUND` (granted separately in Health
  Connect); iOS registers the task in `AppDelegate` + `Info.plist`.

- **App icon + identity.** A "cairn" launcher icon — warm stones balanced into
  a stack on a teal gradient — for Android (adaptive: gradient background +
  stones foreground, plus a legacy/round fallback) and iOS. The art is rendered
  by `tool/generate_icon.py` (Pillow) into `assets/icon/` and turned into
  platform assets by `flutter_launcher_icons`. The app now displays as **Cairn**
  (capital C) on both platforms (Android `android:label`, iOS `CFBundleName`).

- **Per-category detail screens (Phase 4 slice 4).** Tapping a Home card opens a
  focused screen for that metric: **weight** (90-day trend line + latest + net
  change), **steps** (14-day bar chart + today + active-day average), **heart
  rate** (14-day daily-average line + latest / window average / range), and
  **activity** (recent workouts, newest-first, with duration / distance /
  energy). Backed by new query-layer time-series methods (`scalarSeries`,
  `dailySteps`, `dailyHeartRate`, `recentWorkouts`) with their own tests. All
  text is localized (English + German) and numbers are locale-formatted.
- **Backup nudge (§10.2).** A gentle, dismissible Home reminder that the synced
  Nextcloud files are the only long-term copy of the user's history.
- **Internationalization (English + German).** All user-facing text is now
  localized through Flutter's `gen-l10n` ARB workflow (`lib/l10n/app_en.arb`
  template + `app_de.arb`), wired via `flutter_localizations`. The app follows
  the device locale by default; a **language picker** in Settings
  (System / English / Deutsch) overrides it, persisted device-locally in
  `<app-support>/cairn/preferences.json` (a `LocaleStore`/`LocaleController`,
  never synced to Nextcloud). Numbers are locale-formatted via `intl`
  (`72,5 kg` and grouped step counts under `de`); durations use localized unit
  words (`7 Std. 20 Min.`); the German translation uses the informal "du".
  Unit symbols (`kg`, `cm`, `bpm`, `%`, `h`) and ISO dates/24-hour times are
  kept locale-neutral by design. `CairnServices.refresh()` now returns a typed
  `RefreshResult` the UI localizes, so no English strings live in the service
  layer.

- Flutter project scaffold (Android + iOS) with a clean-architecture `lib/src`
  layout and mockable boundary interfaces for health access, OMH mapping,
  local storage, and Nextcloud sync.
- Strict analysis setup (`very_good_analysis` + `strict-casts`/`-inference`/
  `-raw-types`); permissive dependency stack (`health`, `flutter_secure_storage`,
  `http`, `path`, `path_provider`) chosen to keep the app MIT-clean.
- MIT `LICENSE` at the repository root; AGPL boundary for the future Nextcloud
  app documented.
- Project `CLAUDE.md` filled in from the design document.
- `docs/DEVELOPMENT.md` covering Flutter and (future) Nextcloud-app setup.
- `docs/DESIGN.md` §15 — structured development plan and phases.
- **Phase 1 — health read + OMH mapping.** `HealthRepository` over the `health`
  package (read-only, partial-grant + iOS data-presence handling) behind a
  mockable `HealthGateway`; sealed `HealthSample` model; source-priority
  deduplication; `DefaultOmhMapper` emitting heart rate (`omh:heart-rate:1.0`),
  steps (`omh:step-count:3.0`), weight (`omh:body-weight:2.0`), per-stage sleep
  (`cairn:sleep-stage:1.0`) plus aggregated `omh:sleep-episode:1.0`, and workouts
  (IEEE 1752.1 `omh:physical-activity:1.0`); local-offset ISO-8601 timestamps.
- Offline schema-validation tests against vendored OMH + IEEE 1752.1 schemas
  (Apache-2.0) via `json_schema`, plus golden and unit tests.
- **Phase 2 — local persistence.** `JsonlOmhFileStore` writes append-only
  JSON-Lines shards (one file per metric per day) and an atomically-rewritten
  `manifest.json` (`format_version` + per-metric sync anchors, §5.3–5.4); reads
  skip malformed lines and offload large parses to an isolate. A
  `HealthIngestService` reads each metric over the anchor-driven `[lastSync,
  now]` window, maps to OMH, groups by local day, persists, and advances the
  anchor — replacing the fixed look-back. `HealthMetric.slug` and
  `OmhFileStore.setSyncAnchor` added; the debug harness now persists then reads
  back from disk.
- **Phase 3 — Nextcloud connection + sync.** Login Flow v2 (`HttpNextcloudAuth`)
  obtains a revocable app password — never the main password — stored as one
  bundle in OS secure storage (`FlutterSecureTokenStore`); a WebDAV client
  (`WebDavNextcloudSyncTarget`, on `http` + `xml`, not the AGPL `nextcloud`
  client) does `PUT`/`MKCOL`/`PROPFIND`/`GET`. `NextcloudSyncService` pushes the
  local `/Cairn/` tree last-write-wins, driven by a device-local, never-synced
  push journal (`sync_journal.json`): append-only shards re-upload on a size
  delta, `manifest.json` every run. Server-side `(conflicted copy)` files are
  surfaced, never merged. `NextcloudSyncCoordinator` ties connect → sync
  together. Offline appends accumulate and upload on reconnect; remote→local
  pull-merge is deferred to the multi-device phase (§8).
- **Phase 4 (slice 1) — in-app dashboard, sleep deep-dive, BMI.** A read path
  over the local OMH cache (`lib/src/query/`): pure parsers map cache datapoints
  back to typed readings (timezone-correct via `.toLocal()`), and a
  `HealthQueryService` answers latest-weight/heart-rate, today's steps, and
  per-night sleep. A **sleep deep-dive** (the priority screen) renders a
  hypnogram, a stage-duration donut, headline tiles, and a multi-night trend
  (`fl_chart`), reconciling stage segments + the stored episode and
  source-deduplicating. A **dynamic BMI** is computed from the latest weight and
  a synced `profile.json` (height + date of birth, WHO categories, in-norm
  indicator); the height/DoB prompt is a non-blocking card. A Material 3
  navigation shell (Home / Sleep / Settings) replaces the debug dashboard, with
  Nextcloud connection + manual sync + the profile editor in Settings (raw
  ingest/sync harness kept behind `kDebugMode`).
- OS-specific data-source **setup guide** ("Getting your data in", DESIGN.md
  §8): an Android vs iOS walkthrough of installing/using a tracking app, pairing
  a wearable in its vendor app, linking it to Health Connect / Apple Health,
  granting permissions, and letting Cairn read. Reachable from Settings and the
  Sleep empty state; platform is chosen automatically.
- Guided "Connect your Nextcloud" screen (host → Login Flow v2 in the system
  browser via `url_launcher` → poll), now in Settings.
- `.githooks/pre-commit` blocks accidental commits of signing secrets
  (`key.properties`, `*.keystore`/`*.jks`/`*.p12`/`*.pfx`), even via `git add
  -f`; enable per clone with `git config core.hooksPath .githooks`.

### Fixed

- The synced profile now comes back on a fresh install / second device:
  connecting to Nextcloud pulls `profile.json` and adopts it when the remote
  copy is newer than (or absent on) this device (last-write-wins by
  `updated_date_time`), recovering height + date of birth. Sync was otherwise
  push-only. A single-file, size-bounded precursor to the Phase 8 bidirectional
  sync; the append-only health shards still sync push-only (§8).
- Per-category chart Y-axis labels no longer overlap or wrap to two lines when
  the value spread is small (e.g. a weight trend within ~1 kg). The axis now
  snaps to a round step (locale-formatted, e.g. `73,0` under German) with a
  wider gutter, instead of fl_chart's dense, full-precision defaults.
- Backdated / late-arriving health data is now imported: each ingest re-reads a
  trailing reconcile window (default 14 days), not just `[anchor, now]`, so a
  reading logged after a prior sync (e.g. a workout entered this morning) is
  still picked up. Appends are idempotent — a datapoint already on disk
  (matched by content, ignoring its random id/creation time) is not re-written
  — so the overlap never duplicates. Backdating beyond the window still needs
  the change-token work (§4.3, Phase 8).
- BMI updates immediately after editing height/date of birth: the profile is an
  app-wide `ValueNotifier`, so the Home BMI card recomputes without a manual
  refresh.
- Every data screen now updates immediately when new data is ingested: a shared
  `dataRevision` signal (bumped by a centralized `CairnServices.refresh()`)
  reloads Home and the Sleep deep-dive together, so a refresh from any screen
  reflects everywhere — no per-screen manual reload. Concurrent refreshes are
  coalesced into one.
- Workouts now read (Android): authorisation also requests the distance and
  calorie permissions the plugin reads alongside an exercise session, which
  previously failed with a `SecurityException` and returned no activities.
- Sleep now reads (Android): `SLEEP_SESSION` is included, so session-only
  entries (e.g. a manual sleep with no per-stage breakdown) are captured.
- Sleep total uses the union of asleep intervals, so an overall session segment
  is not double-counted against its own stage segments.
- Nextcloud connect no longer hangs on "Waiting for browser authorisation…": a
  secure-storage `PlatformException` on the credential write (common on
  emulators with a reset Keystore) used to escape the poll loop silently. The
  connect/poll paths are now fail-closed (any error surfaces a message), the
  token store recovers from a corrupt entry (delete + retry) and otherwise
  raises a typed error, and a guarded zone in `main.dart` catches stray async
  errors. The poll also treats `3xx` as "still pending" so reverse-proxy /
  sub-path installs complete instead of aborting, and rides out transient
  network/DNS blips (showing "retrying…") rather than failing on the first one.

### Security

- Android release builds use an optional, untracked `key.properties` signing
  config; debug keys remain only as a local-development fallback and never sign
  a distributable artifact.
- Android health permissions are declared **READ-only** (no `WRITE_*`); the app
  never writes to the OS health store.
- Nextcloud sync is **https-only**: the credentials value object rejects a
  non-`https` server, Login Flow v2 rejects a non-`https` host, and Android sets
  `usesCleartextTraffic=false` — Basic auth is never sent in the clear.
- The server-returned Login Flow v2 `login`/`poll.endpoint` URLs are pinned to
  the contacted https host, blocking a malicious server from redirecting the
  browser hand-off (`file:`/`intent:`) or leaking the poll token to an internal
  host (SSRF). The app password lives only in secure storage — never logged,
  never written into the synced tree or the push journal.
- The local-file walk ignores symlinks and refuses paths resolving outside the
  cache; the remote conflict scan is depth-capped against a hostile server.
- The server-returned Login Flow v2 URLs may now be the typed host or a
  sub-domain of it, but never a parent or foreign domain, and the typed host
  must be multi-label — so the relaxation for `apex`→`www` deployments cannot
  be abused to redirect the poll token to an attacker-controlled host.

### Changed

- **Sync now** (Settings) now runs the full cycle — read the OS health store
  *and* upload to Nextcloud — instead of upload-only, and reports what happened
  (pushed/up-to-date counts, conflicts, or "synced locally" when no Nextcloud
  is connected). The app also runs an opportunistic **foreground sync on open**
  (Phase 5, §4.4): screens show cached data instantly, then refresh when new
  readings land. Both reuse the one coalesced refresh path.

### Removed

- The `kDebugMode`-only "Ingest from health store" developer button — its
  manual-read function is now the proper Settings "Sync now".

