# Cairn

**A personal health-data aggregator that you own end to end.**

Cairn reads your wearable and phone health data from the platform's own health
store (Apple HealthKit / Android Health Connect), normalizes it into an open,
documented file format (Open mHealth / IEEE 1752.1, as sharded JSON Lines), and
syncs it into a **Nextcloud you control**. No central server, no proprietary
database, no vendor lock-in — the files in your Nextcloud are the single source
of truth.

It is deliberately aimed at privacy-conscious people and self-hosters who run
(or will happily run) their own Nextcloud. "Bring your own Nextcloud" is the
feature, not a barrier.

## Components

- **Mobile app** (Flutter, iOS + Android) — reads the health store, writes OMH
  files, syncs over WebDAV. The only writer. *(MIT)*
- **Nextcloud web app** ([`nextcloud_app/`](nextcloud_app/), PHP + Vue) — an
  optional, read-only second frontend over the same files, installed onto your
  own Nextcloud. *(AGPL-3.0-or-later)*

## Status

Early development. The mobile app is through its dashboard and sync phases and
into release hardening. The Nextcloud web app has just started: its development
environment and file-reading skeleton exist, and the read-path semantics and Vue
dashboard are next. See the phased plan in
[docs/DESIGN.md §15](docs/DESIGN.md).

## Documentation

- [docs/DESIGN.md](docs/DESIGN.md) — full design and rationale (source of truth).
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — set up a dev environment from
  scratch, for the Flutter app and the Nextcloud app alike.
- [nextcloud_app/README.md](nextcloud_app/README.md) — the web app, and its
  one-command dev environment (`nextcloud_app/dev up`).
- [CHANGELOG.md](CHANGELOG.md) — notable changes.

## License

The mobile app and the OMH file format are released under the
[MIT License](LICENSE). The Nextcloud web app ships from its own subtree under
[AGPL-3.0-or-later](nextcloud_app/LICENSE), because it bundles the AGPL/GPL
`@nextcloud/*` frontend packages into the JavaScript it distributes; see
[docs/DEVELOPMENT.md §5](docs/DEVELOPMENT.md).

## Not a medical device

Cairn aggregates and visualizes data. It makes no diagnostic, treatment, or
clinical claims.
