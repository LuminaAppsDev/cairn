<!--
SPDX-FileCopyrightText: 2026 Max Fiedler
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Cairn for Nextcloud

An optional, **read-only** second frontend over the health files the Cairn phone
app writes into your own Nextcloud. It reads `/Cairn/`, aggregates server-side,
and renders the result. It never writes — see [Read-only, provably](#read-only-provably).

The files are the system of record. This app is a replaceable reader on top of
them, and deleting it loses nothing.

> **Licence note.** This subtree is **AGPL-3.0-or-later**, while the rest of the
> repository is MIT. See [Licence](#licence).

## Get a development environment

Docker is the only prerequisite.

```bash
nextcloud_app/dev up
```

That starts a throwaway Nextcloud, installs it, enables this app, loads health
data, and prints where to go — <http://localhost:8080>, user `admin`, password
`admin`. The app is bind-mounted from your working tree, so editing a PHP file
and reloading the page is the whole edit loop. No build step, no rebuild.

If you have no Cairn data, you still get a populated instance: the environment
generates a synthetic tree that is structurally identical to a real export.

```
./dev up [--no-seed]   Start it. Idempotent — safe to re-run.
./dev seed [DIR]       Reload health data from DIR, or from the resolved default.
./dev deps             Install dependencies and build the bundle. Needed once.
./dev build            Rebuild the frontend.
./dev watch            Rebuild the frontend on every save.
./dev test [ARGS...]   Unit and parity tests, on the container's PHP.
./dev lint             psalm, PHP coding standard, frontend lint, guards.
./dev matrix           Run against every Nextcloud major info.xml claims.
./dev refresh          Bump asset URLs after editing a static file by hand.
./dev check            Read-only guard + info.xml schema validation.
./dev status           Running? App enabled?
./dev occ ARGS...      Any occ command, e.g. ./dev occ app:list
./dev logs [-f]        Tail the server log.
./dev shell            Root shell in the container.
./dev down             Stop, keeping data.
./dev reset            Destroy everything, including seeded data.
```

**PHP and templates need no step** — save and reload. (`up` sets
`opcache.revalidate_freq=0`; the image ships 60, which means an edited file
keeps serving its previous version for up to a minute.)

**Anything under `src/` needs `./dev build`**, or `./dev watch` to rebuild on
save. Both bump the asset cachebuster for you, which is necessary because
Nextcloud serves the bundle `immutable` with a year-long max-age and only that
cachebuster varies its URL.

## Where the health data comes from

`./dev seed` resolves a source in this order, first hit wins:

1. the path you pass — `./dev seed ~/Downloads/Cairn`
2. `CAIRN_SEED_DIR` in `docker/.env`
3. `dev-data/local/` — gitignored; drop an export in here
4. a synthetic tree from `tool/generate_dev_health_data.py`, generated on demand

Point any of them at the `Cairn` folder **itself** — the one holding
`manifest.json` and the metric directories — not at its parent.

### A real export is personal health data

It never enters this repository. `dev-data/` and `docker/.env` are gitignored,
and `.githooks/pre-commit` refuses them even if `git add -f` got past that.

Seeded data is copied into a Docker volume. **`./dev reset` is how you erase
it** — stopping the container is not enough.

### The synthetic tree is not random noise

`tool/generate_dev_health_data.py` plants, deliberately and by date, every case
where a plausible-looking reader disagrees with the phone app about the same
bytes: cumulative whole-day step snapshots that must resolve to the newest,
source priority outranking a later ingest, a superseded weight correction, sleep
windows on both sides of the 60-minute episode gap, segments deduplicated with
the stage excluded from the key, and a handful of malformed lines. It prints
what it planted and why. Run it directly to read the catalogue:

```bash
python3 tool/generate_dev_health_data.py --out /tmp/cairn --force
```

## Read-only, provably

`docs/DESIGN.md` §7 makes read-only the app's entire contract: a second writer
turns a folder of append-only shards into a folder of conflict copies. Prose
alone does not hold, so the property is enforced in layers:

| Layer | Mechanism |
|---|---|
| One seam | Only `NextcloudShardSource` and `CairnRootLocator` may import `OCP\Files\*`. Nothing but decoded objects leaves them, so no writable handle escapes. |
| Read modes only | `fopen('r')`; never `putContent`, `newFile`, `delete`, `move`, `touch`. |
| GET only | Every route in `appinfo/routes.php` is a GET. |
| No write surface | `info.xml` declares no background jobs, repair steps, commands or Sabre plugins, and there is no `lib/Migration/` — the app owns no table. |
| Enforced statically | `tests/read_only_guard.php` fails the build on any of the above, and fails closed if it scanned nothing. |
| Enforced by the mount | The dev container mounts the app `:ro`. |
| No dependencies | `composer.json` requires no libraries, so nothing ships that was not written here. |

Run the first five with `./dev check`.

## Layout

```
appinfo/     info.xml (id, licence, Nextcloud compatibility), routes.php
lib/
  AppInfo/   application bootstrap
  Controller/ PageController — resolves the user, renders the template
  Service/   CairnRootLocator, NextcloudShardSource — the only storage access
             ManifestReader, OverviewService — pure, server-free, testable
templates/   main.php — server-rendered landing page
css/         cairn.css — themed via Nextcloud custom properties
src/         the Vue dashboard: App.vue, hand-rolled SVG charts, no chart library
l10n/        translations (German; English is the source language)
tests/       read_only_guard.php, validate_info_xml.php — zero-dependency checks
             Unit/ — the read-path suite, incl. the shared parity cases
psalm.xml    static analysis, level 2, no baseline
.php-cs-fixer.dist.php  Nextcloud's coding standard
docker/      compose.yaml, .env.example — the dev instance
dev          the entrypoint for all of the above
```

## Status

Early, but the engine is real. `lib/Reading/` implements the read semantics of
`docs/DESIGN.md` §4.3 — last-ingested-wins, source-priority dedup, sleep-episode
aggregation — with no Nextcloud imports at all, and the current page shows
figures computed from your actual shards.

Those rules are held to the same answers as the Flutter app by the shared
fixtures in [`test/fixtures/parity/`](../test/fixtures/parity/), which both
suites run.

The dashboard is a Vue app over a read-only JSON API, with charts hand-rolled
as inline SVG — a charting library would be a large dependency, a
Content-Security-Policy conversation and a second theming system to reconcile
with Nextcloud's, for five charts of two shapes.

## Version tracking

`info.xml`'s version range is a promise to everyone installing from the app
store: a stale `max-version` means the app is silently disabled on their server
after they upgrade (`docs/DESIGN.md` §7). `./dev matrix` checks the promise
instead of asserting it — every claimed major installed in turn, plus a parse of
every file under the PHP floor, which none of the Nextcloud images ships.

`info.xml`'s range, the `MATRIX_IMAGES` table in `dev`, and
`docker/compose.yaml`'s default image are one claim written three times. Move
them together.

## Licence

**AGPL-3.0-or-later** (see [`LICENSE`](LICENSE)), while the mobile app and the
on-disk format in the rest of this repository are MIT.

The Nextcloud app store does not require this — it accepts MIT, Apache-2.0 and
others. What requires it is the frontend: `@nextcloud/vue` and
`@nextcloud/vite-config` are AGPL-3.0-or-later, and `@nextcloud/router`,
`/l10n` and `/initial-state` are GPL-3.0-or-later. Those get compiled into the
`js/` bundle this app ships, which is plain distribution of a combined work.
Using the Nextcloud toolkit is a deliberate choice — it is what makes this look
and behave like the rest of the server — and this licence is its consequence.

See `docs/DEVELOPMENT.md` §5.
