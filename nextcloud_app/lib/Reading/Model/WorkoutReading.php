<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Model;

use DateTimeImmutable;
use OCA\Cairn\Reading\Json\Timestamps;

/**
 * A workout, from the IEEE 1752.1 physical-activity schema.
 *
 * The body carries a `duration` field, and it is deliberately not stored here:
 * the mobile reader recomputes duration from the interval and ignores what the
 * source claimed. Keeping the stated value would let a source whose arithmetic
 * disagrees with its own timestamps show one number on the phone and another on
 * the web.
 */
final class WorkoutReading {
	public function __construct(
		public readonly string $activityName,
		public readonly DateTimeImmutable $start,
		public readonly DateTimeImmutable $end,
		public readonly ?float $distanceMeters = null,
		public readonly ?float $kcal = null,
		public readonly ?int $steps = null,
		public readonly ?ReadingSource $source = null,
	) {
	}

	/** Elapsed wall-clock duration, in milliseconds. */
	public function durationMillis(): int {
		return Timestamps::elapsedMillis($this->start, $this->end);
	}
}
