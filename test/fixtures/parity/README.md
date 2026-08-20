<!--
SPDX-FileCopyrightText: 2026 Max Fiedler
SPDX-License-Identifier: MIT
-->

# Cross-frontend parity fixtures

`docs/DESIGN.md` §4.3 says the read semantics are a property of the **file
format**, not of any one reader: the mobile dashboard and the Nextcloud web app
must produce the same answers from the same bytes, or the files stop being a
single source of truth. Two independent implementations of a dozen subtle rules
do not stay in agreement because everyone meant well. They stay in agreement
because something fails when they drift.

That is what lives here. Each case is a miniature `/Cairn/` folder, a set of
questions to ask of it, and the answers both readers must give. The Dart suite
and the PHP suite each run every case:

| Reader | Runner |
|---|---|
| Flutter app | `test/parity/parity_test.dart` — `flutter test` |
| Nextcloud app | `nextcloud_app/tests/Unit/ParityTest.php` — `nextcloud_app/dev test` |

Neither runner can pass by skipping: both fail if they find no cases, and both
fail on a query name they do not implement. Adding a query to one frontend's
fixture therefore forces the other to implement it.

## A case

```
cases/<nn>-<slug>/
  spec.json       what "now" is, which timezone, and which queries to ask
  tree/           a /Cairn folder: <metric>/<year>/<date>.jsonl
  expected.json   the answers, keyed by query id
```

`spec.json`:

```json
{
  "description": "why this case exists, and what a wrong reader does",
  "now": "2026-08-20T12:00:00",
  "timezone": "Europe/Berlin",
  "queries": [
    { "id": "today", "name": "todayStepTotal" },
    { "id": "week", "name": "dailySteps", "days": 7 }
  ]
}
```

## Encoding

Both readers serialise results the same way, so a diff is a real disagreement
rather than a formatting one.

| Kind | Encoding |
|---|---|
| Instant | `YYYY-MM-DDTHH:MM:SS+HH:MM`, rendered in the case's timezone |
| Calendar date | `YYYY-MM-DD` |
| Duration | whole **milliseconds**, as an integer |
| Measured value | JSON number; compared with a tolerance of 1e-9 |
| Absent | `null` — every field is always present, so `null` never means "missing key" |
| Lists | compared **in order**; read order is part of the semantics |

## The timezone is load-bearing

Cases are authored in `Europe/Berlin` because it has daylight saving, and the
interesting failures cluster at the two boundaries. PHP takes the zone as a
parameter. Dart does not — it reads the process zone — so the Dart suite must
run with `TZ=Europe/Berlin`:

```bash
TZ=Europe/Berlin flutter test
```

The Dart runner checks this and fails with that command in the message rather
than producing quietly wrong answers. It also asserts the actual UTC offsets on
a winter and a summer date, which catches the subtler failure of the two hosts
carrying different `tzdata`.

## Adding a case

Keep the tree small enough that the expected answers can be worked out by hand
and checked by a reviewer — the goldens exist to encode *intent*, so generating
them from whichever reader currently exists would defeat the purpose. Name the
case after the rule it protects, and say in `description` what a wrong reader
does, not just what the right one does.

## Licence

These fixtures are MIT, like the rest of the repository outside
`nextcloud_app/`. The PHP runner that consumes them lives in that subtree and is
AGPL-3.0-or-later; reading a data file does not change either.
