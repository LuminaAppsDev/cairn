# Changelog

All notable changes to this project are documented in this file.

## Unreleased

### Added

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

