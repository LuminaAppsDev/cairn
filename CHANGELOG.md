# Changelog

All notable changes to this project are documented in this file.

## Unreleased

### Added

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

