# Changelog

All notable changes to this project are documented in this file.

## Unreleased

### Added

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

### Removed

