#!/usr/bin/env python3
"""Generate a synthetic ``/Cairn/`` tree for the Nextcloud app's dev environment.

WHY THIS SCRIPT EXISTS.

The Nextcloud web app (``docs/DESIGN.md`` §7) is a read-only consumer of the OMH
JSON-Lines files the mobile app writes. To develop it you need a populated
``/Cairn/`` folder — but the only real such folder is a person's health history,
which must never be committed to this repository. Without a substitute, a
first-time contributor's dev instance comes up empty and every screen is blank.

So this script fabricates a structurally exact tree that nobody's body produced.
It is *not* a random-noise generator: each of the read path's genuinely tricky
cases is planted deliberately by its own named function, which makes this file
double as executable documentation of the semantics in ``docs/DESIGN.md`` §4.3.
Those cases are the ones where a plausible-looking reader silently disagrees with
the mobile app on the same bytes:

1. Cumulative whole-day step snapshots that must resolve to the newest, never the
   sum and never the first.
2. Source priority beating a later ingest timestamp, and ingest time breaking a
   tie only at equal priority.
3. An in-place value correction superseded by ``header.creation_date_time``.
4. Provenance that is all-or-nothing: a ``source_name`` without a ``modality``
   yields *no* source at all.
5. Sleep-stage segments deduplicated on their window alone, with the stage
   deliberately excluded from the key.
6. The 60-minute episode gap tolerance, on both sides of the boundary.
7. Malformed lines that must be skipped without breaking the surrounding day.

Output is deterministic for a given ``--seed``, so a regenerated tree produces an
empty diff and dev instances are reproducible across machines.

Run from the project root::

    python3 tool/generate_dev_health_data.py

Exit status: 0 wrote a tree, 1 refused to overwrite an existing one, 2 the
arguments could not be used.
"""

from __future__ import annotations

import argparse
import json
import random
import shutil
import sys
import uuid
from collections import Counter
from collections.abc import Callable
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any, Final, NamedTuple
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

# The datapoint builders below take one keyword-only argument per OMH field,
# which is what makes every call site read like the JSON it produces; collapsing
# them behind config objects would hide exactly the shape this file exists to
# document. And the module is deliberately one catalogue rather than a package:
# a contributor meeting the read semantics for the first time should be able to
# scroll it end to end.
# pylint: disable=too-many-arguments,too-many-lines

# Resolved from this file, never from the working directory, so the script
# behaves identically from a shell, the `dev` script, or a CI step.
REPO_ROOT: Final[Path] = Path(__file__).resolve().parent.parent
DEFAULT_OUT: Final[Path] = REPO_ROOT / "nextcloud_app" / "dev-data" / "generated"

# Every metric directory the mobile app writes (lib/src/health/health_metric.dart).
SLUGS: Final[tuple[str, ...]] = ("heart-rate", "steps", "sleep", "activity", "weight")

# The edge cases below are planted on fixed offsets back from the end date, so a
# contributor can find any one of them by date. The tree must be long enough to
# hold every offset in PLANTERS, plus the one-day margin the sleep cases need on
# either side (a night's evening segments land in the previous day's shard).
MIN_DAYS: Final[int] = 37


class Source(NamedTuple):
    """An ``acquisition_provenance`` pair: who reported a reading, and how."""

    name: str
    modality: str


# The real export's source. Matches no wearable fragment, so it ranks lowest
# (5) under SourcePriorityPolicy.defaults() in lib/src/health/source_dedup.dart.
SAMSUNG: Final[Source] = Source("com.sec.android.app.shealth", "sensed")
# Health Connect's own per-interval step deltas, alongside Samsung's daily total.
PHONE: Final[Source] = Source("android", "sensed")
# Contains "fit", so it ranks 3 — strictly better than either of the above. This
# is the source that must win a contested window on rank alone.
WEARABLE: Final[Source] = Source("Galaxy Fit3", "sensed")
# A hand-typed reading: same name, self-reported modality, loses the sleep
# dedup's automatic-over-manual tie-break.
MANUAL: Final[Source] = Source("com.sec.android.app.shealth", "self-reported")
# A second automatic source for weight, to prove same-instant readings from
# different sources do NOT collapse.
SCALE: Final[Source] = Source("Withings Body+", "sensed")


class Tree:
    """Accumulates JSON-Lines shards, then writes them as a ``/Cairn/`` folder.

    Lines are kept in insertion order per shard because read order is part of the
    observable semantics: ties in every dedup rule resolve to first-seen.
    """

    def __init__(self) -> None:
        """Create an empty tree."""
        self._shards: dict[tuple[str, date], list[str]] = {}
        self._notes: list[str] = []

    def add(self, slug: str, when: datetime, point: dict[str, Any]) -> None:
        """Append ``point`` to the shard for ``slug`` on ``when``'s local date."""
        self.add_raw(slug, when.date(), json.dumps(point, separators=(",", ":")))

    def add_raw(self, slug: str, day: date, line: str) -> None:
        """Append a verbatim ``line`` — used to plant deliberately broken JSON."""
        self._shards.setdefault((slug, day), []).append(line)

    def note(self, message: str) -> None:
        """Record a planted edge case for the run summary."""
        self._notes.append(message)

    @property
    def notes(self) -> list[str]:
        """The planted-edge-case summary, in planting order."""
        return list(self._notes)

    def counts(self) -> Counter[str]:
        """Shard count per metric slug."""
        return Counter(slug for slug, _ in self._shards)

    def write(self, root: Path) -> None:
        """Write each shard as ``<slug>/<yyyy>/<date>.jsonl`` under ``root``."""
        for (slug, day), lines in sorted(
            self._shards.items(), key=lambda kv: (kv[0][0], kv[0][1])
        ):
            shard = root / slug / f"{day.year:04d}" / f"{day.isoformat()}.jsonl"
            shard.parent.mkdir(parents=True, exist_ok=True)
            # A trailing newline on the final line, matching the mobile app's
            # append path — a shard that ends mid-line means a torn write.
            shard.write_text("".join(f"{line}\n" for line in lines), encoding="utf-8")


def _iso(when: datetime) -> str:
    """Format ``when`` the way the mobile app does: whole seconds, local offset."""
    return when.isoformat(timespec="seconds")


def _uuid(rng: random.Random) -> str:
    """Draw a deterministic UUID-v4 string from ``rng``."""
    return str(uuid.UUID(int=rng.getrandbits(128), version=4))


def _header(
    rng: random.Random,
    *,
    namespace: str,
    name: str,
    version: str,
    ingested: datetime,
    source: Source | None,
    source_created: datetime | None = None,
    omit_ingested: bool = False,
    omit_modality: bool = False,
) -> dict[str, Any]:
    """Build an OMH ``header`` block.

    ``omit_ingested`` drops ``creation_date_time`` so the reading can never win a
    last-ingested-wins tie-break. ``omit_modality`` drops ``modality`` alone,
    which makes the whole provenance block unparseable — the reading then behaves
    as if it had no source at all, despite carrying a perfectly good name.
    """
    header: dict[str, Any] = {"id": _uuid(rng)}
    if not omit_ingested:
        header["creation_date_time"] = _iso(ingested)
    header["schema_id"] = {"namespace": namespace, "name": name, "version": version}
    if source is not None:
        provenance: dict[str, Any] = {"source_name": source.name}
        if not omit_modality:
            provenance["modality"] = source.modality
        if source_created is not None:
            provenance["source_creation_date_time"] = _iso(source_created)
        header["acquisition_provenance"] = provenance
    return header


def _scalar(
    rng: random.Random,
    *,
    namespace: str,
    name: str,
    version: str,
    field: str,
    value: float,
    unit: str,
    at: datetime,
    ingested: datetime,
    source: Source | None = SAMSUNG,
    omit_ingested: bool = False,
    omit_modality: bool = False,
) -> dict[str, Any]:
    """Build a point-in-time datapoint (heart rate, body weight)."""
    return {
        "header": _header(
            rng,
            namespace=namespace,
            name=name,
            version=version,
            ingested=ingested,
            source=source,
            source_created=at,
            omit_ingested=omit_ingested,
            omit_modality=omit_modality,
        ),
        "body": {
            field: {"value": value, "unit": unit},
            "effective_time_frame": {"date_time": _iso(at)},
        },
    }


def _interval_frame(start: datetime, end: datetime) -> dict[str, Any]:
    """Build an ``effective_time_frame`` spanning ``[start, end]``."""
    return {
        "time_interval": {"start_date_time": _iso(start), "end_date_time": _iso(end)}
    }


def _steps(
    rng: random.Random,
    *,
    value: float,
    start: datetime,
    end: datetime,
    ingested: datetime,
    source: Source = SAMSUNG,
    omit_ingested: bool = False,
) -> dict[str, Any]:
    """Build an ``omh:step-count`` datapoint over ``[start, end]``."""
    return {
        "header": _header(
            rng,
            namespace="omh",
            name="step-count",
            version="3.0",
            ingested=ingested,
            source=source,
            source_created=start,
            omit_ingested=omit_ingested,
        ),
        "body": {
            "step_count": {"value": value, "unit": "steps"},
            "effective_time_frame": _interval_frame(start, end),
        },
    }


def _stage(
    rng: random.Random,
    *,
    stage: str,
    start: datetime,
    end: datetime,
    ingested: datetime,
    source: Source = SAMSUNG,
    schema_name: str = "sleep-stage",
    namespace: str = "cairn",
    version: str = "1.0",
) -> dict[str, Any]:
    """Build a ``cairn:sleep-stage`` segment."""
    return {
        "header": _header(
            rng,
            namespace=namespace,
            name=schema_name,
            version=version,
            ingested=ingested,
            source=source,
            source_created=start,
        ),
        "body": {
            "sleep_stage": stage,
            "effective_time_frame": _interval_frame(start, end),
        },
    }


def _episode(
    rng: random.Random,
    *,
    start: datetime,
    end: datetime,
    total_minutes: float,
    ingested: datetime,
    is_main: bool = True,
    awakenings: int = 0,
    light: float | None = None,
    deep: float | None = None,
    rem: float | None = None,
    main_sleep_as_string: bool = False,
) -> dict[str, Any]:
    """Build an ``omh:sleep-episode`` rollup.

    ``main_sleep_as_string`` emits ``"true"`` rather than ``true`` — a reader
    using loose comparison would wrongly accept it.
    """
    body: dict[str, Any] = {
        "effective_time_frame": _interval_frame(start, end),
        "total_sleep_time": {"value": total_minutes, "unit": "min"},
        "is_main_sleep": "true" if main_sleep_as_string else is_main,
        "number_of_awakenings": awakenings,
    }
    for field, minutes in (
        ("light_sleep_duration", light),
        ("deep_sleep_duration", deep),
        ("rem_sleep_duration", rem),
    ):
        if minutes is not None:
            body[field] = {"value": minutes, "unit": "min"}
    return {
        "header": _header(
            rng,
            namespace="omh",
            name="sleep-episode",
            version="1.0",
            ingested=ingested,
            source=SAMSUNG,
            source_created=start,
        ),
        "body": body,
    }


def _workout(
    rng: random.Random,
    *,
    activity: str,
    start: datetime,
    end: datetime,
    ingested: datetime,
    source: Source = SAMSUNG,
    distance_m: float | None = None,
    kcal: float | None = None,
    steps: float | None = None,
    duration_minutes: float | None = None,
) -> dict[str, Any]:
    """Build an ``omh:physical-activity`` datapoint.

    ``duration_minutes`` overrides the emitted ``duration`` field. The read path
    ignores it and recomputes ``end - start``, so a disagreeing value is a probe
    for a reader that wrongly trusts it.
    """
    span = (end - start).total_seconds() / 60.0
    body: dict[str, Any] = {
        "activity_name": activity,
        "effective_time_frame": _interval_frame(start, end),
        "duration": {
            "value": span if duration_minutes is None else duration_minutes,
            "unit": "min",
        },
    }
    if distance_m is not None:
        body["distance"] = {"value": distance_m, "unit": "m"}
    if kcal is not None:
        body["kcal_burned"] = {"value": kcal, "unit": "kcal"}
    if steps is not None:
        body["base_movement_quantity"] = {"value": steps, "unit": "steps"}
    return {
        "header": _header(
            rng,
            namespace="omh",
            name="physical-activity",
            version="1.0",
            ingested=ingested,
            source=source,
            source_created=start,
        ),
        "body": body,
    }


def _at(
    day: date, tz: ZoneInfo, hour: int, minute: int = 0, second: int = 0
) -> datetime:
    """A wall-clock instant on ``day`` in ``tz``, with the correct DST offset."""
    return datetime(day.year, day.month, day.day, hour, minute, second, tzinfo=tz)


def _baseline_heart_rate(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """Emit a day of resting/active heart-rate samples from the vendor app."""
    ingested = _at(day, tz, 23, 55)
    for slot in range(28):
        at = _at(day, tz, 0, 0) + timedelta(minutes=slot * 51 + rng.randrange(0, 30))
        if at.date() != day:
            continue
        # Lower overnight, higher through the afternoon — enough shape that the
        # daily min/max/mean roll-up shows something recognisable.
        base = 52 if at.hour < 6 else 68 + (12 if 15 <= at.hour < 21 else 0)
        tree.add(
            "heart-rate",
            at,
            _scalar(
                rng,
                namespace="omh",
                name="heart-rate",
                version="1.0",
                field="heart_rate",
                value=float(base + rng.randrange(-4, 9)),
                unit="beats/min",
                at=at,
                ingested=ingested,
            ),
        )


def _baseline_steps(tree: Tree, rng: random.Random, day: date, tz: ZoneInfo) -> None:
    """Emit a day of steps the way Samsung Health really reports them.

    One whole-day record whose value climbs through the day, re-read on every
    sync, plus Health Connect's own short per-interval deltas. The day's total is
    the newest whole-day snapshot PLUS the distinct deltas — summing the
    snapshots themselves would wildly over-count.
    """
    start, end = _at(day, tz, 0, 0, 0), _at(day, tz, 23, 59, 59)
    total = 0.0
    for hour in (8, 12, 16, 20, 23):
        total += float(rng.randrange(900, 2600))
        tree.add(
            "steps",
            start,
            _steps(
                rng,
                value=total,
                start=start,
                end=end,
                ingested=_at(day, tz, hour, 42),
            ),
        )
    for burst in range(rng.randrange(2, 6)):
        walk = _at(day, tz, 7 + burst * 3, rng.randrange(0, 59))
        tree.add(
            "steps",
            walk,
            _steps(
                rng,
                value=float(rng.randrange(3, 40)),
                start=walk,
                end=walk + timedelta(seconds=rng.randrange(4, 120)),
                ingested=_at(day, tz, 23, 42),
                source=PHONE,
            ),
        )


def _baseline_sleep(tree: Tree, rng: random.Random, day: date, tz: ZoneInfo) -> None:
    """Emit one night of stage segments, spanning midnight into ``day``.

    Segments land in the shard of their own start date, so an evening onset is
    written to the previous day's file — exactly what the mobile app does, and a
    case the reader's date-range enumeration has to cover.
    """
    ingested = _at(day, tz, 7, 30)
    cursor = _at(day - timedelta(days=1), tz, 23, 10) + timedelta(
        minutes=rng.randrange(0, 40)
    )
    wake = _at(day, tz, 6, 30) + timedelta(minutes=rng.randrange(0, 35))
    cycle = ("light", "deep", "light", "rem")
    index = 0
    while cursor < wake:
        stage = cycle[index % len(cycle)] if rng.randrange(0, 9) else "awake"
        span = timedelta(
            minutes=rng.randrange(8, 34) if stage != "awake" else rng.randrange(1, 5)
        )
        segment_end = min(cursor + span, wake)
        tree.add(
            "sleep",
            cursor,
            _stage(
                rng,
                stage=stage,
                start=cursor,
                end=segment_end,
                ingested=ingested,
            ),
        )
        cursor, index = segment_end, index + 1


def _baseline_weight(tree: Tree, rng: random.Random, day: date, tz: ZoneInfo) -> None:
    """Emit a morning weigh-in on most days — people skip some."""
    if rng.randrange(0, 5) == 0:
        return
    at = _at(day, tz, 6, 15) + timedelta(minutes=rng.randrange(0, 45))
    tree.add(
        "weight",
        at,
        _scalar(
            rng,
            namespace="omh",
            name="body-weight",
            version="2.0",
            field="body_weight",
            value=round(87.0 + rng.random() * 2.4, 1),
            unit="kg",
            at=at,
            ingested=_at(day, tz, 23, 55),
        ),
    )


def _baseline_activity(tree: Tree, rng: random.Random, day: date, tz: ZoneInfo) -> None:
    """Emit a workout on roughly two days in five."""
    if rng.randrange(0, 5) >= 2:
        return
    start = _at(day, tz, 17, rng.randrange(0, 50))
    minutes = rng.randrange(11, 55)
    end = start + timedelta(minutes=minutes)
    tree.add(
        "activity",
        start,
        _workout(
            rng,
            activity=rng.choice(("WALKING", "RUNNING", "CYCLING")),
            start=start,
            end=end,
            ingested=_at(day, tz, 23, 55),
            distance_m=float(minutes * rng.randrange(55, 95)),
            kcal=float(minutes * rng.randrange(4, 9)),
            steps=float(minutes * rng.randrange(50, 70)),
        ),
    )


def _plant_steps_out_of_order(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """Cumulative snapshots written in non-monotonic *physical* order.

    The ingest stamps still rise, so the day's total is decided by
    ``creation_date_time`` and not by which line happens to come last.
    """
    start, end = _at(day, tz, 0, 0, 0), _at(day, tz, 23, 59, 59)
    for value, hour in ((14210.0, 22), (3100.0, 9), (9040.0, 15)):
        tree.add(
            "steps",
            start,
            _steps(
                rng,
                value=value,
                start=start,
                end=end,
                ingested=_at(day, tz, hour, 5),
            ),
        )
    tree.note(
        f"{day}: steps — snapshots out of line order; the total is"
        " 14210, not 3100 and not the 26350 sum"
    )


def _plant_steps_without_ingest(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """A snapshot with no ``creation_date_time`` must never displace a dated one."""
    start, end = _at(day, tz, 0, 0, 0), _at(day, tz, 23, 59, 59)
    tree.add(
        "steps",
        start,
        _steps(
            rng,
            value=7700.0,
            start=start,
            end=end,
            ingested=_at(day, tz, 21, 0),
        ),
    )
    tree.add(
        "steps",
        start,
        _steps(
            rng,
            value=999999.0,
            start=start,
            end=end,
            ingested=_at(day, tz, 23, 0),
            omit_ingested=True,
        ),
    )
    tree.note(f"{day}: steps — undated 999999 snapshot must lose to the dated 7700")


def _plant_steps_source_priority(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """Source priority outranks a later ingest on a contested window.

    The wearable's name contains "fit" (rank 3); the vendor app matches nothing
    (rank 5). The vendor record is ingested *later* on purpose: a reader that
    tie-breaks on ingest time before consulting priority picks the wrong one.
    """
    start = _at(day, tz, 12, 0, 0)
    end = start + timedelta(minutes=30)
    tree.add(
        "steps",
        start,
        _steps(
            rng,
            value=2400.0,
            start=start,
            end=end,
            ingested=_at(day, tz, 12, 40),
            source=WEARABLE,
        ),
    )
    tree.add(
        "steps",
        start,
        _steps(
            rng,
            value=1150.0,
            start=start,
            end=end,
            ingested=_at(day, tz, 20, 10),
            source=SAMSUNG,
        ),
    )
    tree.note(
        f"{day}: steps — wearable 2400 beats the later-ingested" " vendor 1150 on rank"
    )


def _plant_steps_equal_rank_tie(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """At equal source priority, the later-ingested reading takes the window."""
    start = _at(day, tz, 14, 0, 0)
    end = start + timedelta(minutes=10)
    tree.add(
        "steps",
        start,
        _steps(
            rng,
            value=310.0,
            start=start,
            end=end,
            ingested=_at(day, tz, 14, 30),
            source=PHONE,
        ),
    )
    tree.add(
        "steps",
        start,
        _steps(
            rng,
            value=845.0,
            start=start,
            end=end,
            ingested=_at(day, tz, 18, 30),
            source=PHONE,
        ),
    )
    tree.note(f"{day}: steps — equal rank, so the later-ingested 845 wins the window")


def _plant_weight_correction(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """A re-typed weight: same source, same instant, superseded by ingest time."""
    at = _at(day, tz, 6, 21)
    tree.add(
        "weight",
        at,
        _scalar(
            rng,
            namespace="omh",
            name="body-weight",
            version="2.0",
            field="body_weight",
            value=98.4,
            unit="kg",
            at=at,
            ingested=_at(day, tz, 6, 25),
        ),
    )
    tree.add(
        "weight",
        at,
        _scalar(
            rng,
            namespace="omh",
            name="body-weight",
            version="2.0",
            field="body_weight",
            value=88.4,
            unit="kg",
            at=at,
            ingested=_at(day, tz, 9, 2),
        ),
    )
    tree.note(
        f"{day}: weight — corrected 88.4 supersedes the mistyped"
        " 98.4 at the same instant"
    )


def _plant_weight_distinct_sources(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """Same instant, different sources — these must NOT collapse into one."""
    at = _at(day, tz, 6, 40)
    for source, value in ((SAMSUNG, 88.1), (SCALE, 88.6)):
        tree.add(
            "weight",
            at,
            _scalar(
                rng,
                namespace="omh",
                name="body-weight",
                version="2.0",
                field="body_weight",
                value=value,
                unit="kg",
                at=at,
                ingested=_at(day, tz, 7, 0),
                source=source,
            ),
        )
    tree.note(f"{day}: weight — two sources at one instant stay two readings")


def _plant_weight_without_provenance(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """No provenance block at all: both fall in the '' bucket and DO collapse."""
    at = _at(day, tz, 6, 50)
    for value, hour in ((77.0, 7), (88.7, 11)):
        tree.add(
            "weight",
            at,
            _scalar(
                rng,
                namespace="omh",
                name="body-weight",
                version="2.0",
                field="body_weight",
                value=value,
                unit="kg",
                at=at,
                ingested=_at(day, tz, hour, 0),
                source=None,
            ),
        )
    tree.note(f"{day}: weight — unattributed readings share the '' key, so 88.7 wins")


def _plant_weight_name_without_modality(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """A ``source_name`` with no ``modality`` yields *no* source at all.

    Provenance is all-or-nothing, so despite carrying a good name this reading
    collapses against unattributed ones rather than against its namesake.
    """
    at = _at(day, tz, 6, 55)
    tree.add(
        "weight",
        at,
        _scalar(
            rng,
            namespace="omh",
            name="body-weight",
            version="2.0",
            field="body_weight",
            value=88.9,
            unit="kg",
            at=at,
            ingested=_at(day, tz, 8, 0),
            omit_modality=True,
        ),
    )
    tree.add(
        "weight",
        at,
        _scalar(
            rng,
            namespace="omh",
            name="body-weight",
            version="2.0",
            field="body_weight",
            value=66.6,
            unit="kg",
            at=at,
            ingested=_at(day, tz, 7, 0),
            source=None,
        ),
    )
    tree.note(
        f"{day}: weight — name without modality means no source; 88.9 wins the '' key"
    )


def _segments(
    tree: Tree,
    rng: random.Random,
    ingested: datetime,
    spans: tuple[tuple[datetime, datetime, str], ...],
    source: Source = SAMSUNG,
) -> None:
    """Write a run of sleep-stage segments, each into the shard of its own start."""
    for start, end, stage in spans:
        tree.add(
            "sleep",
            start,
            _stage(
                rng,
                stage=stage,
                start=start,
                end=end,
                ingested=ingested,
                source=source,
            ),
        )


def _plant_sleep_gap_boundary(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """Both sides of the 60-minute episode gap tolerance, in one night.

    A 45-minute break keeps one episode; a 90-minute break starts a second. The
    morning nap is the shorter of the two, so exactly one episode is main.
    """
    prev = day - timedelta(days=1)
    ingested = _at(day, tz, 9, 0)
    _segments(
        tree,
        rng,
        ingested,
        (
            (_at(prev, tz, 23, 20), _at(day, tz, 1, 0), "light"),
            # 45-minute gap — under tolerance, so still the same episode.
            (_at(day, tz, 1, 45), _at(day, tz, 3, 30), "deep"),
            (_at(day, tz, 3, 30), _at(day, tz, 5, 30), "rem"),
            # 90-minute gap — over tolerance, so a new episode begins.
            (_at(day, tz, 7, 0), _at(day, tz, 8, 0), "light"),
        ),
    )
    tree.note(
        f"{day}: sleep — 45min gap keeps one episode, 90min gap starts a second (nap)"
    )


def _plant_sleep_main_sleep_tie(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """Two episodes with exactly equal sleep on one date — both are main."""
    ingested = _at(day, tz, 12, 0)
    _segments(
        tree,
        rng,
        ingested,
        (
            (_at(day, tz, 2, 0), _at(day, tz, 4, 0), "deep"),
            (_at(day, tz, 9, 0), _at(day, tz, 11, 0), "deep"),
        ),
    )
    tree.note(f"{day}: sleep — two 120-minute episodes tie, so both are flagged main")


def _plant_sleep_overlapping_session(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """A whole-night ``session`` segment overlapping its own sub-stages.

    Total sleep is the *union* of asleep intervals, so it stays at the session's
    390 minutes. Adding the sub-stages on top would report over eleven hours.
    """
    prev = day - timedelta(days=1)
    ingested = _at(day, tz, 8, 0)
    _segments(
        tree,
        rng,
        ingested,
        (
            (_at(prev, tz, 23, 30), _at(day, tz, 6, 0), "session"),
            (_at(prev, tz, 23, 40), _at(day, tz, 1, 0), "light"),
            (_at(day, tz, 1, 0), _at(day, tz, 3, 0), "deep"),
            (_at(day, tz, 3, 0), _at(day, tz, 5, 30), "rem"),
        ),
    )
    tree.note(
        f"{day}: sleep — session overlaps its sub-stages; the union stays 390 min"
    )


def _plant_sleep_duplicate_window(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """One window reported twice with *different* stages.

    The stage is deliberately absent from the dedup key, so these collapse to one
    segment and the higher-ranked wearable decides which stage survives. A reader
    that keys on the stage as well keeps both and invents an awakening.
    """
    ingested = _at(day, tz, 8, 30)
    start, end = _at(day, tz, 2, 0), _at(day, tz, 2, 40)
    _segments(tree, rng, ingested, ((start, end, "deep"),), source=WEARABLE)
    _segments(tree, rng, ingested, ((start, end, "awake"),), source=SAMSUNG)
    _segments(
        tree,
        rng,
        ingested,
        (
            (_at(day, tz, 0, 30), _at(day, tz, 2, 0), "light"),
            (_at(day, tz, 2, 40), _at(day, tz, 5, 0), "rem"),
        ),
    )
    tree.note(
        f"{day}: sleep — same window, two stages; the wearable's"
        " 'deep' wins, so no awakening is counted"
    )


def _plant_sleep_manual_duplicate(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """At equal source rank, an automatic segment beats a self-reported one."""
    ingested = _at(day, tz, 8, 30)
    start, end = _at(day, tz, 1, 0), _at(day, tz, 4, 0)
    _segments(tree, rng, ingested, ((start, end, "deep"),), source=SAMSUNG)
    _segments(tree, rng, ingested, ((start, end, "awake"),), source=MANUAL)
    tree.note(
        f"{day}: sleep — sensed 'deep' beats the self-reported"
        " 'awake' on the same window"
    )


def _plant_sleep_stored_episode_disagrees(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """A stored ``sleep-episode`` whose numbers contradict the segments.

    Stored episodes are cross-reference only — every reader renders the values
    recomputed from the stage segments, so these 999s must never reach a screen.
    """
    ingested = _at(day, tz, 8, 0)
    start, end = _at(day, tz, 1, 0), _at(day, tz, 5, 0)
    _segments(
        tree,
        rng,
        ingested,
        (
            (start, _at(day, tz, 3, 0), "light"),
            (_at(day, tz, 3, 0), end, "deep"),
        ),
    )
    tree.add(
        "sleep",
        start,
        _episode(
            rng,
            start=start,
            end=end,
            total_minutes=999.0,
            ingested=ingested,
            awakenings=99,
            light=999.0,
            deep=999.0,
            rem=999.0,
        ),
    )
    tree.note(
        f"{day}: sleep — stored episode claims 999 min; the recomputed 240 must win"
    )


def _plant_sleep_episode_without_stages(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """An episode with no stage segments anywhere yields no night at all."""
    start, end = _at(day, tz, 0, 30), _at(day, tz, 6, 30)
    tree.add(
        "sleep",
        start,
        _episode(
            rng,
            start=start,
            end=end,
            total_minutes=330.0,
            ingested=_at(day, tz, 8, 0),
            main_sleep_as_string=True,
        ),
    )
    tree.note(
        f'{day}: sleep — episode-only day (and a string "true") produces no night'
    )


def _plant_sleep_unknown_schema(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """An unrecognised schema name is dropped; an odd namespace/version is not.

    Only ``header.schema_id.name`` discriminates inside ``sleep/`` — namespace and
    version are ignored entirely.
    """
    ingested = _at(day, tz, 8, 0)
    start, end = _at(day, tz, 1, 30), _at(day, tz, 4, 30)
    tree.add(
        "sleep",
        start,
        _stage(
            rng,
            stage="deep",
            start=start,
            end=end,
            ingested=ingested,
            namespace="omh",
            version="9.9",
        ),
    )
    tree.add(
        "sleep",
        start,
        _stage(
            rng,
            stage="deep",
            start=_at(day, tz, 4, 30),
            end=_at(day, tz, 5, 30),
            ingested=ingested,
            schema_name="sleep-nonsense",
        ),
    )
    tree.note(f"{day}: sleep — 'omh'/9.9 stage is kept, 'sleep-nonsense' is dropped")


def _plant_activity_duplicate_sources(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """No dedup runs on activity, so one workout from two sources is listed twice."""
    start = _at(day, tz, 18, 0)
    end = start + timedelta(minutes=42)
    for source in (SAMSUNG, WEARABLE):
        tree.add(
            "activity",
            start,
            _workout(
                rng,
                activity="RUNNING",
                start=start,
                end=end,
                ingested=_at(day, tz, 19, 0),
                source=source,
                distance_m=6400.0,
                kcal=380.0,
                steps=5900.0,
            ),
        )
    tree.note(
        f"{day}: activity — the same run from two sources is listed twice (no dedup)"
    )


def _plant_activity_duration_disagrees(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """The body's ``duration`` is ignored; duration is recomputed as end - start."""
    start = _at(day, tz, 17, 15)
    end = start + timedelta(minutes=25)
    tree.add(
        "activity",
        start,
        _workout(
            rng,
            activity="CYCLING",
            start=start,
            end=end,
            ingested=_at(day, tz, 19, 0),
            distance_m=8100.0,
            kcal=210.0,
            steps=0.0,
            duration_minutes=999.0,
        ),
    )
    tree.note(
        f"{day}: activity — body duration says 999 min; the shown value must be 25"
    )


def _plant_malformed_lines(
    tree: Tree, rng: random.Random, day: date, tz: ZoneInfo
) -> None:
    """Broken lines that must be skipped without disturbing the good ones.

    Each is placed on a day that also carries ordinary readings, so "the day
    still renders" is what gets verified rather than "the file was ignored".
    """
    at = _at(day, tz, 10, 0)
    tree.add(
        "heart-rate",
        at,
        _scalar(
            rng,
            namespace="omh",
            name="heart-rate",
            version="1.0",
            field="heart_rate",
            value=61.0,
            unit="beats/min",
            at=at,
            ingested=_at(day, tz, 11, 0),
        ),
    )
    # A value delivered as a string is not a number under strict typing.
    tree.add_raw(
        "heart-rate",
        day,
        json.dumps(
            {
                "header": _header(
                    rng,
                    namespace="omh",
                    name="heart-rate",
                    version="1.0",
                    ingested=_at(day, tz, 11, 0),
                    source=SAMSUNG,
                ),
                "body": {
                    "heart_rate": {"value": "62", "unit": "beats/min"},
                    "effective_time_frame": {"date_time": _iso(_at(day, tz, 10, 5))},
                },
            },
            separators=(",", ":"),
        ),
    )
    # A unit-value with no unit is dropped, taking the whole reading with it.
    tree.add_raw(
        "heart-rate",
        day,
        json.dumps(
            {
                "header": _header(
                    rng,
                    namespace="omh",
                    name="heart-rate",
                    version="1.0",
                    ingested=_at(day, tz, 11, 0),
                    source=SAMSUNG,
                ),
                "body": {
                    "heart_rate": {"value": 63.0},
                    "effective_time_frame": {"date_time": _iso(_at(day, tz, 10, 10))},
                },
            },
            separators=(",", ":"),
        ),
    )
    # An unparseable timestamp drops the reading rather than raising.
    tree.add_raw(
        "heart-rate",
        day,
        json.dumps(
            {
                "header": _header(
                    rng,
                    namespace="omh",
                    name="heart-rate",
                    version="1.0",
                    ingested=_at(day, tz, 11, 0),
                    source=SAMSUNG,
                ),
                "body": {
                    "heart_rate": {"value": 64.0, "unit": "beats/min"},
                    "effective_time_frame": {"date_time": "not-a-timestamp"},
                },
            },
            separators=(",", ":"),
        ),
    )
    # Valid JSON that is not a top-level object.
    tree.add_raw("heart-rate", day, '["not","an","object"]')
    tree.add_raw("heart-rate", day, "")
    tree.add_raw("heart-rate", day, "   ")
    # A torn append from a process killed mid-write. Deliberately last: this is
    # the only position a real torn line can occupy.
    tree.add_raw("heart-rate", day, '{"header":{"id":"9f0c1f2e-0000-4000-8000-0000000')
    tree.note(
        f"{day}: heart-rate — 7 malformed lines beside good ones;"
        " the day must still render"
    )


# Each planter runs on ``end_date - offset``. Offsets are fixed so a contributor
# can navigate straight to a case by date, and so regenerating with the same seed
# reproduces the tree exactly.
PLANTERS: Final[dict[int, Callable[[Tree, random.Random, date, ZoneInfo], None]]] = {
    1: _plant_steps_out_of_order,
    2: _plant_steps_without_ingest,
    3: _plant_steps_source_priority,
    4: _plant_steps_equal_rank_tie,
    5: _plant_weight_correction,
    6: _plant_weight_distinct_sources,
    7: _plant_weight_without_provenance,
    8: _plant_weight_name_without_modality,
    9: _plant_activity_duplicate_sources,
    10: _plant_activity_duration_disagrees,
    11: _plant_sleep_gap_boundary,
    14: _plant_sleep_main_sleep_tie,
    17: _plant_sleep_overlapping_session,
    20: _plant_sleep_duplicate_window,
    23: _plant_sleep_manual_duplicate,
    26: _plant_sleep_stored_episode_disagrees,
    29: _plant_sleep_episode_without_stages,
    32: _plant_sleep_unknown_schema,
    35: _plant_malformed_lines,
}

# Offsets whose planter writes its own night. Baseline sleep is suppressed on
# each of these and on both neighbours, because a night's evening segments land
# in the previous day's shard — without the margin, a planted episode would be
# glued to a generated one and stop demonstrating anything.
SLEEP_PLANT_OFFSETS: Final[tuple[int, ...]] = (11, 14, 17, 20, 23, 26, 29, 32)


def _suppressed_sleep_offsets() -> frozenset[int]:
    """Offsets on which the generated baseline night must not be written."""
    return frozenset(
        offset + delta for offset in SLEEP_PLANT_OFFSETS for delta in (-1, 0, 1)
    )


def build_tree(*, days: int, end_day: date, tz: ZoneInfo, seed: int) -> Tree:
    """Build the whole tree: a baseline for every day, plus the planted cases."""
    tree = Tree()
    rng = random.Random(seed)
    suppressed = _suppressed_sleep_offsets()
    for offset in range(days - 1, -1, -1):
        day = end_day - timedelta(days=offset)
        _baseline_heart_rate(tree, rng, day, tz)
        _baseline_steps(tree, rng, day, tz)
        _baseline_weight(tree, rng, day, tz)
        _baseline_activity(tree, rng, day, tz)
        if offset not in suppressed:
            _baseline_sleep(tree, rng, day, tz)
    # Planted last so a case is always the visible anomaly on its day, and in
    # ascending offset order so the summary reads newest-first.
    for offset in sorted(PLANTERS):
        PLANTERS[offset](tree, rng, end_day - timedelta(days=offset), tz)
    return tree


def _write_metadata(root: Path, *, end_day: date, tz: ZoneInfo) -> None:
    """Write ``manifest.json`` and ``profile.json`` beside the metric folders."""
    updated = _iso(_at(end_day, tz, 23, 59))
    manifest = {
        "format_version": 1,
        "generator": "cairn",
        "updated_date_time": updated,
        "sync_anchors": {slug: updated for slug in SLUGS},
        "devices": [],
    }
    profile = {
        "format_version": 1,
        "generator": "cairn",
        "updated_date_time": updated,
        "height": {"value": 178.0, "unit": "cm"},
        "date_of_birth": "1988-05-17",
    }
    for name, payload in (("manifest.json", manifest), ("profile.json", profile)):
        (root / name).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def _refuse_to_delete(out: Path) -> str | None:
    """Why ``--force`` must not recursively delete ``out``, or ``None`` if it may.

    ``--force`` is a recursive delete of a path the caller chose, so a mistyped
    ``--out ~`` would be unrecoverable. The check is deliberately conservative:
    it recognises a directory this script produced and refuses everything else
    it cannot vouch for. Normal use — the dev environment's fixture directory,
    or a fresh scratch path — never reaches this code, because an empty or
    absent directory is not deleted at all.
    """
    if out.parent == out:
        return "it is a filesystem root"
    for anchor in (Path.home(), REPO_ROOT):
        if out == anchor:
            return f"it is {anchor}"
    # A tree this script wrote always has a manifest.json beside the metric
    # folders. Anything else is somebody's real directory that is in the way.
    if not (out / "manifest.json").is_file():
        return "it has no manifest.json, so it was not generated by this script"
    return None


def _parse_args(argv: list[str]) -> argparse.Namespace:
    """Parse and validate the command line."""
    parser = argparse.ArgumentParser(
        description="Generate a synthetic /Cairn/ tree for the Nextcloud"
        " app's dev environment.",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_OUT,
        help=f"destination folder (default: {DEFAULT_OUT.relative_to(REPO_ROOT)})",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=45,
        help=f"how many days to generate, at least {MIN_DAYS} (default: 45)",
    )
    parser.add_argument(
        "--end-date",
        default=None,
        help="last day to generate, as YYYY-MM-DD (default: today)",
    )
    parser.add_argument(
        "--tz",
        default="Europe/Berlin",
        help="IANA zone the wall-clock times are written in"
        " (default: Europe/Berlin)",
    )
    parser.add_argument(
        "--seed", type=int, default=1988, help="RNG seed (default: 1988)"
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="replace the destination if it already exists",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Generate the tree. Returns the process exit status."""
    args = _parse_args(sys.argv[1:] if argv is None else argv)

    if args.days < MIN_DAYS:
        print(
            f"--days {args.days} is too short: the planted edge cases reach "
            f"{max(PLANTERS)} days back, so at least {MIN_DAYS} are needed.",
            file=sys.stderr,
        )
        return 2
    try:
        tz = ZoneInfo(args.tz)
    except (ZoneInfoNotFoundError, ValueError):
        print(f"--tz {args.tz!r} is not an IANA timezone name.", file=sys.stderr)
        print("Use something like Europe/Berlin or America/New_York.", file=sys.stderr)
        return 2
    try:
        end_day = (
            date.today() if args.end_date is None else date.fromisoformat(args.end_date)
        )
    except ValueError:
        print(
            f"--end-date {args.end_date!r} is not a YYYY-MM-DD date.", file=sys.stderr
        )
        return 2

    out: Path = args.out.expanduser().resolve()
    if out.exists() and any(out.iterdir()):
        if not args.force:
            print(f"{out} already exists and is not empty.", file=sys.stderr)
            print(
                "Pass --force to replace it, or --out to write somewhere else.",
                file=sys.stderr,
            )
            return 1
        refusal = _refuse_to_delete(out)
        if refusal is not None:
            print(f"refusing to delete {out}: {refusal}", file=sys.stderr)
            print(
                "Point --out at a directory that only holds generated data.",
                file=sys.stderr,
            )
            return 2
        shutil.rmtree(out)
    out.mkdir(parents=True, exist_ok=True)

    tree = build_tree(days=args.days, end_day=end_day, tz=tz, seed=args.seed)
    tree.write(out)
    _write_metadata(out, end_day=end_day, tz=tz)

    counts = tree.counts()
    print(f"Wrote {sum(counts.values())} shards to {out}")
    print(f"  {args.days} days ending {end_day}, timezone {args.tz}, seed {args.seed}")
    for slug in SLUGS:
        print(f"  {slug:<12} {counts.get(slug, 0):>3} shards")
    print("\nPlanted edge cases — each one is a place a plausible reader goes wrong:")
    for note in tree.notes:
        print(f"  {note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
