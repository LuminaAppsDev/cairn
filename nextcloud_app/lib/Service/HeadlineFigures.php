<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Service;

/**
 * A few numbers read out of the files by the ported read path.
 *
 * Deliberately small. The point of showing them on the skeleton page is not the
 * dashboard — that comes later — but evidence that the semantics in
 * `lib/Reading/` produce sane answers against a real folder, which no unit test
 * can demonstrate.
 */
final class HeadlineFigures {
	public function __construct(
		public readonly ?float $todaySteps,
		public readonly ?float $latestWeightKg,
		public readonly ?string $latestWeightAt,
		public readonly ?int $lastNightSleepMillis,
		public readonly ?string $lastNightOn,
		public readonly ?float $lastNightEfficiency,
		public readonly int $workoutsLast7Days,
		public readonly ?float $restingHeartRate,
	) {
	}
}
