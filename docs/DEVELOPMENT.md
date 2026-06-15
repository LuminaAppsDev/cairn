# Cairn — Development Setup

How to set up a working development environment from scratch, for both
components:

1. the **Flutter mobile app** (iOS + Android) — the v1 deliverable, and
2. the **Nextcloud web app** (PHP + Vue) — a later stage (DESIGN.md §7, §11).

> Cairn is intentionally niche (privacy-conscious self-hosters). You will need
> your own Nextcloud to exercise the full sync path — see §3.6.

---

## 1. Repository layout

```
lib/                       → Flutter app source (Dart)
  main.dart                → entrypoint
  src/
    app.dart               → root MaterialApp widget
    dashboard/             → in-app dashboard (reads local OMH cache)
    health/                → OS health-store access (read-only seam + models)
    omh/                   → Open mHealth / IEEE 1752.1 mapping
    storage/               → append-only sharded JSONL file store
    sync/                  → Nextcloud WebDAV sync, Login Flow v2, secure tokens
test/                      → Dart/Flutter tests
android/ ios/              → platform projects (Android + iOS only)
docs/                      → DESIGN.md (source of truth), this file
analysis_options.yaml      → strict lint config (very_good_analysis + strict-*)
```

The `lib/src/*` boundary files are **abstract interfaces** around every native
capability (health, secure storage, WebDAV) so they can be mocked and tested in
isolation (DESIGN.md §13). Implementations are added per development phase
(DESIGN.md §15).

---

## 2. Common prerequisites

| Tool | Version | Notes |
|---|---|---|
| Flutter SDK | **3.44.0** (stable) | Pins Dart **3.12.0**. Pin the SDK for the team — `fvm` recommended (see §3.1). |
| Git | any recent | — |
| A Nextcloud instance | 28+ | Your own; for full end-to-end sync testing (§3.6). |

Platform toolchains (Android Studio / Xcode) are covered in §3.3 and §3.4.

---

## 3. Mobile app (Flutter)

### 3.1 Install Flutter

Follow the official guide: <https://docs.flutter.dev/get-started/install>.

Pin the version so everyone builds with the same toolchain. Recommended via
[`fvm`](https://fvm.app):

```bash
dart pub global activate fvm
fvm install 3.44.0
fvm use 3.44.0          # writes .fvmrc; prefix commands with `fvm flutter ...`
```

(If you use a system-wide Flutter instead, just ensure `flutter --version`
reports 3.44.0.)

### 3.2 Get the project and verify the toolchain

```bash
git clone https://github.com/TheFlipside/cairn.git
cd cairn
flutter pub get
flutter doctor          # resolve any reported toolchain gaps before continuing
```

### 3.3 Android setup (Health Connect)

Android reads health data through **Health Connect**, which has hard
requirements:

- **Install Android Studio** (bundles the SDK, platform tools, and an emulator
  image), or the command-line SDK.
- **Already configured (Phase 1), no action needed:** `minSdk = 26`
  ([`build.gradle.kts`](../android/app/build.gradle.kts)); `MainActivity` extends
  `FlutterFragmentActivity`; and `AndroidManifest.xml` declares the Health
  Connect `<queries>`, the permission-rationale activity, and **READ-only**
  permissions for the five v1 metrics (`READ_HEART_RATE`, `READ_STEPS`,
  `READ_WEIGHT`, `READ_EXERCISE`, `READ_SLEEP`) plus `ACTIVITY_RECOGNITION`.
  Cairn never requests WRITE (DESIGN.md §2). Background-read is deferred to
  Phase 5. If you bump the `health` package, re-check its README for manifest
  drift: <https://pub.dev/packages/health>.
- **Health Connect must be present on the device/emulator.** It is built in on
  Android 14+; on older versions install the Health Connect app from the Play
  Store. The emulator needs a Google-APIs/Play system image.
- **Release signing (distribution only).** Local `flutter run --release` works
  out of the box (it falls back to debug signing). For a distributable build,
  create an untracked `android/key.properties` with `storeFile`, `storePassword`,
  `keyAlias`, and `keyPassword` pointing at your release keystore — both
  `key.properties` and `*.jks` are gitignored, so debug keys never sign a shipped
  artifact.

Because Health Connect has no Wear OS support and is fed by the vendor app, real
data flow also depends on the user's onboarding (DESIGN.md §8); for development,
seed data via a vendor app or the Health Connect "sample data" tooling.

### 3.4 iOS setup (HealthKit)

> Requires **macOS + Xcode**. Deployment target is **iOS 13.0**.

- **The one manual step:** open `ios/Runner.xcworkspace` in Xcode, set your
  signing **Team**, and under **Signing & Capabilities** add the **HealthKit**
  capability (this writes the entitlement, which can't be set from Dart). For
  background sync, also enable HealthKit **Background Delivery** (Phase 5).
- `NSHealthShareUsageDescription` (read justification) is **already set** in
  [`ios/Runner/Info.plist`](../ios/Runner/Info.plist). Cairn is read-only, so it
  does not declare `NSHealthUpdateUsageDescription`; if a future toolchain demands
  it at build time, add it with a read-only-framed string.
- Note HealthKit hides read-authorisation status by design — the UI keys off
  data presence, not a permission boolean (DESIGN.md §4.2).

### 3.5 Run, test, and the quality gate

```bash
flutter run                                       # pick a device/emulator
flutter test                                      # unit + widget tests

# Quality gate — must be clean before committing (DESIGN.md §13):
dart format .
dart analyze                                      # zero issues
dart format --output=none --set-exit-if-changed . # CI format assertion
```

`dart analyze` is configured strict (`very_good_analysis` + `strict-casts` /
`strict-inference` / `strict-raw-types`); treat every lint as an error.

### 3.6 Connecting a Nextcloud (end-to-end sync)

Full sync needs a reachable Nextcloud over HTTPS. The app uses **Login Flow v2**
to obtain an app password (never your main password) and **WebDAV** to write the
`/Cairn/` tree (DESIGN.md §6). For local development, run Nextcloud via Docker
and expose it over HTTPS (a reverse proxy or `--scheme https`), since Login Flow
v2 and secure storage assume TLS.

---

## 4. Nextcloud web app (PHP + Vue) — later stage

A separate, **read-only** consumer of the `/Cairn/` files, installed onto the
user's own Nextcloud (DESIGN.md §7). Not part of v1; set this up only when
starting the v1.5 phase (DESIGN.md §15).

### 4.1 Prerequisites

| Tool | Notes |
|---|---|
| PHP | Match the target Nextcloud's supported PHP (8.1+ for current releases). |
| Composer | PHP dependency manager. |
| Node.js + npm | Builds the Vue frontend. |
| A Nextcloud dev instance | See §4.2. |

### 4.2 A Nextcloud development instance

Use the maintained dev environment
[`nextcloud-docker-dev`](https://github.com/juliusknorr/nextcloud-docker-dev),
or bind-mount the app into a plain Nextcloud container's `custom_apps/`
directory. The server's admin `occ` CLI is used to enable apps.

### 4.3 Scaffold, build, enable

- Generate the app skeleton from
  <https://apps.nextcloud.com/developer/apps/generate>, or copy an existing
  minimal app. It lives in a dedicated subtree of this repo
  (proposed: `nextcloud_app/`).
- `appinfo/info.xml` must declare the licence. Per the Nextcloud app store this
  app is **AGPL-3.0-or-later** (`<licence>agpl</licence>`) — see §5.
- Build:

  ```bash
  composer install        # PHP deps
  npm ci && npm run build  # Vue frontend bundle
  ```

- Enable on your dev instance:

  ```bash
  occ app:enable cairn
  ```

- **Version-track against Nextcloud majors.** Keep `info.xml`'s
  `max-version` current or the app is disabled on server upgrade
  (DESIGN.md §7).

Reference: Nextcloud Developer Manual —
<https://docs.nextcloud.com/server/latest/developer_manual/>.

---

## 5. Licensing boundary (important)

- The **mobile app and the OMH file format are MIT** (root `LICENSE`). All
  runtime dependencies are permissive (MIT / BSD-3-Clause). We deliberately do
  **not** use the AGPL-licensed `nextcloud` Dart client — WebDAV and Login
  Flow v2 are implemented over the permissive `http` package — so importing it
  would relicense the whole app to AGPL.
- The **Nextcloud web app links AGPL Nextcloud server code** and ships via the
  NC app store, so its subtree carries its **own AGPL-3.0-or-later licence**.
  MIT and AGPL coexist cleanly via per-directory licensing.

---

## 6. Before you commit

**One-time setup:** activate the secret-guard hook in your clone:

```bash
git config core.hooksPath .githooks
```

It refuses to commit signing secrets (`key.properties`, keystores) even if
`git add -f` bypassed `.gitignore`.

The pre-commit gate is binding — see [CLAUDE.md](../CLAUDE.md):

1. Run `/review` and `/security-audit`; resolve all findings.
2. Record changes in [CHANGELOG.md](../CHANGELOG.md).
3. Final action before `git add`: `dart format .` then
   `dart format --output=none --set-exit-if-changed .`.
