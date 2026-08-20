<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Model;

use DateTimeImmutable;

/**
 * A measurement spanning a window: a step count over an interval.
 *
 * The window matters as much as the value. A source that re-reports a
 * *cumulative* total in a fixed window — Samsung Health exposes the day's steps
 * as one whole-day record whose value climbs — produces a fresh line with an
 * identical window on every sync. Those collapse to the newest. Genuine
 * per-interval deltas keep distinct windows and are summed (DESIGN.md §4.3).
 */
final class IntervalReading {
	public function __construct(
		public readonly float $value,
		public readonly string $unit,
		public readonly DateTimeImmutable $start,
		public readonly DateTimeImmutable $end,
		public readonly ?ReadingSource $source = null,
		public readonly ?DateTimeImmutable $ingestedAt = null,
	) {
	}
}
