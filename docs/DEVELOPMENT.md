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
nextcloud_app/             → the read-only Nextcloud web app (PHP + Vue, AGPL — §4, §5)
tool/                      → repo tooling (Python); incl. the dev-data generator
analysis_options.yaml      → strict lint config (very_good_analysis + strict-*)
.flake8                    → flake8 aligned to black's 88 columns (tool/*.py)
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
git clone https://github.com/LuminaAppsDev/cairn.git
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

## 4. Nextcloud web app (PHP + Vue)

A separate, **read-only** consumer of the `/Cairn/` files, installed onto the
user's own Nextcloud (DESIGN.md §7). It lives in [`nextcloud_app/`](../nextcloud_app/),
which has its own [README](../nextcloud_app/README.md) and its own licence (§5).

### 4.1 Prerequisites

**Docker, and nothing else.** PHP, Composer and Node all run inside the dev
container, so there is no host toolchain to match against the server's.

(The container runs PHP 8.5, which is what Nextcloud 34 ships. If you also have
PHP on your host it is probably a different minor — prefer the container for
anything you intend to trust.)

### 4.2 Bring it up

```bash
nextcloud_app/dev up
```

One command: starts a pinned Nextcloud, waits out its first-run install, enables
the app, loads health data, and prints the URL — <http://localhost:8080>, user
`admin`, password `admin`. It is idempotent, so re-running it is the way to
recover a confused instance.

The app is bind-mounted from your working tree, so the edit loop is *edit a PHP
file, reload the page*. There is no build step and nothing to copy.

```
./dev up [--no-seed]   Start it. Safe to re-run.
./dev seed [DIR]       Reload health data.
./dev refresh          Bump asset URLs after editing CSS, JS or an icon.
./dev check            Read-only guard + info.xml schema validation.
./dev status           Running? App enabled?
./dev occ ARGS...      Any occ command, e.g. ./dev occ app:list
./dev logs [-f]        Tail the server log.
./dev shell            Root shell in the container.
./dev down             Stop, keeping data.
./dev reset            Destroy everything, including seeded data.
```

PHP and templates need nothing: save the file and reload. **Static assets — CSS,
JavaScript, icons — need `./dev refresh`**, because Nextcloud serves them
`immutable` with a year-long max-age and only a server-side cachebuster varies
the URL. Skipping it means hunting for a hard reload in every browser.

`up` also switches Nextcloud's local cache off. The image enables APCu, whose
memory is per-process, so `occ` updates the database and the CLI's cache while
the Apache worker keeps serving what it cached earlier — config changes appear
to be accepted and then do nothing. On a single-user dev container that is a far
worse trade than the lost caching.

Earlier revisions of this document recommended
[`nextcloud-docker-dev`](https://github.com/juliusknorr/nextcloud-docker-dev).
It is a fine project, but it is a second repository to clone with its own
conventions and it wants your app inside *its* workspace. `nextcloud_app/docker/compose.yaml`
is around fifty readable lines instead, which is the better trade for one app.

### 4.3 Health data for the dev instance

`./dev seed` resolves a source in this order, first hit wins:

1. the path you pass — `./dev seed ~/Downloads/Cairn`
2. `CAIRN_SEED_DIR` in `nextcloud_app/docker/.env` (gitignored, created on first run)
3. `nextcloud_app/dev-data/local/` — gitignored; drop an export in here
4. a synthetic tree from `tool/generate_dev_health_data.py`, generated on demand

Point any of them at the `Cairn` folder **itself** — the one holding
`manifest.json` — not at its parent. That is the usual mistake.

Because of step 4, a fresh clone with no data at all still comes up populated.
The generated tree is not random noise: it plants, by date, every case where a
plausible reader disagrees with the phone app about the same bytes (cumulative
step snapshots, source priority beating a later ingest, a superseded weight
correction, sleep gaps either side of the 60-minute episode tolerance,
deliberately malformed lines). It prints what it planted and why.

> **A real export is personal health data.** It never enters this repository:
> `dev-data/` and `docker/.env` are gitignored, and `.githooks/pre-commit`
> refuses them even if `git add -f` got past that (§6). Seeded data is copied
> into a Docker volume — **`./dev reset` is how you erase it**; stopping the
> container is not enough.

### 4.4 Checks

```bash
nextcloud_app/dev check
```

Runs, inside the container:

- **`tests/read_only_guard.php`** — a static scan proving the app has no write
  path: no mutating filesystem call anywhere in `lib/`, no `fopen` in a mode
  other than read, and `OCP\Files\*` imported only by the two classes allowed
  to touch storage. It fails closed if it scanned nothing, because a guard that
  reports all-clear while checking nothing is worse than no guard.
- **`tests/validate_info_xml.php`** — validates `appinfo/info.xml` against the
  app store's own schema (cached at `tests/fixtures/info.xsd`), and asserts the
  licence is AGPL-3.0-or-later and that no write surface is declared.

Both are plain PHP with no Composer and no PHPUnit, so they run anywhere `php`
does.

Dependencies and the frontend bundle are a one-time step:

```bash
nextcloud_app/dev deps     # Composer + npm + a first build, all containerised
nextcloud_app/dev test     # runs on the server's own PHP, not your host's
nextcloud_app/dev lint     # psalm, PHP coding standard, frontend lint, guards
```

The edit loop differs by layer, and it is worth knowing which:

| You changed | What to do |
|---|---|
| PHP, templates | Save and reload. `up` sets `opcache.revalidate_freq=0`; the image ships 60, which would serve the previous version for up to a minute. |
| `src/` (Vue) | `./dev build`, or leave `./dev watch` running. Both bump the asset cachebuster. |
| A static file by hand | `./dev refresh` — Nextcloud serves assets `immutable` with a year-long max-age. |

PHP is analysed, not merely syntax-checked. `psalm` runs at level 2 against
`nextcloud/ocp` stubs pinned to **Nextcloud 32** — the lowest version
`info.xml` claims — so calling an API added in 33 or 34 is a finding here
rather than a broken install for somebody on 32. There is deliberately **no
psalm baseline**: a baseline records the mistakes that existed when it was
written and permits them for ever. Findings get fixed, or suppressed in
`psalm.xml` with the reason written next to them.

Formatting follows `nextcloud/coding-standard` — the same reasoning as the Vite
and ESLint configs. `./dev lint` checks it; `composer cs:fix` applies it.

### 4.5 Cross-frontend parity (important)

`DESIGN.md` §4.3 makes the read semantics a property of the **file format**: the
Flutter app and the Nextcloud app must give the same answers for the same bytes,
or the files stop being a single source of truth. Two independent
implementations of a dozen subtle rules do not stay in agreement because
everyone meant well — they stay in agreement because something fails when they
drift.

[`test/fixtures/parity/`](../test/fixtures/parity/) holds the shared cases: a
miniature `/Cairn/` folder, the questions to ask of it, and the answers both
readers must give. Both suites run all of them, both fail if they find no cases,
and both fail on a query name they do not implement — so adding a query to a
fixture forces the other frontend to implement it.

```bash
TZ=Europe/Berlin flutter test test/parity   # the Flutter half
nextcloud_app/dev test --filter ParityTest  # the Nextcloud half
```

The `TZ` matters: the fixtures are authored in `Europe/Berlin` because it has
daylight saving, and Dart reads its timezone from the environment rather than
taking it as a parameter. CI pins it. The suite checks the resulting offsets and
fails with that command in the message rather than producing quietly wrong
answers.

**If you change a read rule in either frontend, change it in both, and add a
case.** A change that makes one reader disagree with the other is a change to
the format.

### 4.6 Version-tracking against Nextcloud majors

`info.xml`'s `<nextcloud min-version max-version>` is a promise to everyone
installing from the app store, and a stale `max-version` means the app is
silently disabled on their server after they upgrade (DESIGN.md §7). Check the
promise rather than assert it:

```bash
nextcloud_app/dev matrix
```

It installs every claimed Nextcloud major in turn, enables the app, seeds
generated data, and checks the page, the bundle and all six endpoints — plus the
read-only guard and `info.xml` under **that version's PHP**, which differs across
them (32 ships 8.3, 33 ships 8.4, 34 ships 8.5). It also parses every file under
PHP 8.2, the floor `info.xml` declares and which none of the Nextcloud images
ships — without that step, half the compatibility claim would go untested while
looking covered.

It runs as its own Compose project on its own port, so it never disturbs a
`dev up` instance you have open, and tears each version down afterwards.

**Three things move together.** `info.xml`'s version range, the
`MATRIX_IMAGES` table in `nextcloud_app/dev`, and `docker/compose.yaml`'s
default image are one claim expressed three times. Change one and change the
others in the same commit, then run the matrix — the point of it is that the
claim cannot quietly become false.

CI runs the same command (`.forgejo/workflows/nextcloud-matrix.yml`) when the
claim or the environment changes, on demand, and weekly. It is deliberately
*not* on every push: three Nextcloud installs would queue every other job behind
them on a single-runner host. Run it locally before changing read-path code.

Reference: Nextcloud Developer Manual —
<https://docs.nextcloud.com/server/latest/developer_manual/>.

---

## 5. Licensing boundary (important)

- The **mobile app and the OMH file format are MIT** (root `LICENSE`). All
  runtime dependencies are permissive (MIT / BSD-3-Clause). We deliberately do
  **not** use the AGPL-licensed `nextcloud` Dart client — WebDAV and Login
  Flow v2 are implemented over the permissive `http` package — so importing it
  would relicense the whole app to AGPL.
- The **Nextcloud web app subtree carries its own AGPL-3.0-or-later licence**
  (`nextcloud_app/LICENSE`, and `<licence>AGPL-3.0-or-later</licence>` in
  `appinfo/info.xml`). MIT and AGPL coexist cleanly via per-directory licensing.

  The reason is worth stating precisely, because two plausible ones are wrong.
  **It is not an app-store rule** — the store's `info.xsd` accepts `MIT`,
  `Apache-2.0`, `BSD-*`, `MPL-2.0` and more, and apps ship under those today.
  **Nor is it the plugin-linking question** on its own: that is genuinely
  unsettled, MIT is GPL-compatible either way, and Cairn never redistributes
  Nextcloud — the user installs it.

  What binds is the **frontend we bundle**. `@nextcloud/vue` and
  `@nextcloud/vite-config` are AGPL-3.0-or-later; `@nextcloud/router`,
  `@nextcloud/l10n` and `@nextcloud/initial-state` are GPL-3.0-or-later. Those
  are compiled into the `js/` bundle the app ships, which is ordinary
  distribution of a combined work and needs no linking theory at all. Using the
  Nextcloud toolkit is a deliberate choice — it is what makes the app look and
  behave like the rest of the server — and this licence is its consequence.

  The corollary: an MIT web app is possible, but only by avoiding every
  `@nextcloud/*` package, and that has to be decided before the frontend is
  written rather than retrofitted.

---

## 6. Before you commit

**One-time setup:** activate the secret-guard hook in your clone:

```bash
git config core.hooksPath .githooks
```

It refuses to commit, even if `git add -f` bypassed `.gitignore`:

- **signing secrets** — `key.properties`, keystores, `.p12`/`.pfx`;
- **personal health data** — anything under `nextcloud_app/dev-data/`,
  `nextcloud_app/docker/.env`, and any `.jsonl` outside `test/fixtures/`. A
  leaked signing key can be rotated; a leaked health history cannot.

The pre-commit gate is binding — see [CLAUDE.md](../CLAUDE.md):

1. Run `/review` and `/security-audit`; resolve all findings.
2. Record changes in [CHANGELOG.md](../CHANGELOG.md).
3. Final action before `git add`: `dart format .` then
   `dart format --output=none --set-exit-if-changed .`.
