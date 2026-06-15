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
- Debug-only on-device "read health now" harness on the dashboard.
- `.githooks/pre-commit` blocks accidental commits of signing secrets
  (`key.properties`, `*.keystore`/`*.jks`/`*.p12`/`*.pfx`), even via `git add
  -f`; enable per clone with `git config core.hooksPath .githooks`.

### Fixed

- Workouts now read (Android): authorisation also requests the distance and
  calorie permissions the plugin reads alongside an exercise session, which
  previously failed with a `SecurityException` and returned no activities.
- Sleep now reads (Android): `SLEEP_SESSION` is included, so session-only
  entries (e.g. a manual sleep with no per-stage breakdown) are captured.
- Sleep total uses the union of asleep intervals, so an overall session segment
  is not double-counted against its own stage segments.

### Security

- Android release builds use an optional, untracked `key.properties` signing
  config; debug keys remain only as a local-development fallback and never sign
  a distributable artifact.
- Android health permissions are declared **READ-only** (no `WRITE_*`); the app
  never writes to the OS health store.

### Changed

### Removed

