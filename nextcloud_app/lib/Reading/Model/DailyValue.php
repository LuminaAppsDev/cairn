<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Model;

/** One day's total, for a bar chart. `$day` is a local `YYYY-MM-DD` date. */
final class DailyValue {
	public function __construct(
		public readonly string $day,
		public readonly float $value,
	) {
	}
}
