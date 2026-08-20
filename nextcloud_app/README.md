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
./dev refresh          Bump asset URLs after editing CSS, JS or an icon.
./dev check            Read-only guard + info.xml schema validation.
./dev status           Running? App enabled?
./dev occ ARGS...      Any occ command, e.g. ./dev occ app:list
./dev logs [-f]        Tail the server log.
./dev shell            Root shell in the container.
./dev down             Stop, keeping data.
./dev reset            Destroy everything, including seeded data.
```

**PHP and templates need no step at all** — they are read on every request, so
save and reload. **CSS, JavaScript and icons need `./dev refresh`**, because
Nextcloud serves them with `Cache-Control: max-age=15778463, immutable` and the
only thing that varies the URL is a cachebuster the server controls. Without it
you are reaching for a hard reload in every browser you test in.

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
tests/       read_only_guard.php, validate_info_xml.php — zero-dependency checks
docker/      compose.yaml, .env.example — the dev instance
dev          the entrypoint for all of the above
```

## Status

Early. The current page proves the app can find, list and decode the mobile
app's shards, and survives a damaged line. The read-path semantics
(`docs/DESIGN.md` §4.3) — last-ingested-wins, source-priority dedup, sleep
episode aggregation — are **not yet ported**; they land next, together with a
shared golden-fixture harness that holds the Dart and PHP readers to the same
answers. The Vue dashboard follows that.

## Version tracking

`info.xml`'s `max-version` must move with each Nextcloud major or the app is
disabled on upgrade (`docs/DESIGN.md` §7). Bump it only after checking the app
still enables against the new major, and move `docker/compose.yaml`'s pinned
image at the same time.

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
