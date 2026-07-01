# Changelog

All notable changes to this project are documented in this file.

## Unreleased

### Fixed

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

- **Redesigned the sleep-stage hypnogram.** The "Stages through the night"
  chart was a single-colour stepped line whose vertical transitions through the
  middle "Light" band made the night look noisy and left every phase the same
  colour. It now draws one coloured bar per stage segment — colours matching the
  "Where the night went" donut — so deep / light / REM / awake stand apart at a
  glance.

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

