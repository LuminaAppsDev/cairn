<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Model;

/**
 * One day's spread for a metric sampled many times a day, such as heart rate.
 *
 * `$count` is carried because a day's mean is only as meaningful as the number
 * of samples behind it — a window average has to weight by it rather than
 * averaging the daily means.
 */
final class DailyStat {
	public function __construct(
		public readonly string $day,
		public readonly float $min,
		public readonly float $max,
		public readonly float $mean,
		public readonly int $count,
	) {
	}
}
