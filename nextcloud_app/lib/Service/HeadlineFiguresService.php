<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Service;

use OCA\Cairn\Reading\HealthQueryService;
use OCA\Cairn\Reading\Model\HealthMetric;
use OCA\Cairn\Reading\SystemClock;

/** Runs the ported read path over one user's folder. */
class HeadlineFiguresService {
	public function __construct(
		private readonly NextcloudShardSource $shards,
		private readonly DisplayTimeZone $timeZone,
	) {
	}

	public function forUser(string $userId): HeadlineFigures {
		$display = $this->timeZone->get();
		$queries = new HealthQueryService(
			shards: new UserShardSource($this->shards, $userId),
			clock: new SystemClock($display),
			display: $display,
		);

		$weight = $queries->latestScalar(HealthMetric::Weight);
		$night = $queries->lastNight();
		$heartRates = $queries->dailyHeartRate(7);

		// The lowest daily minimum across the week is a rough resting rate —
		// enough to show the daily roll-up works, not a clinical figure.
		$resting = null;
		foreach ($heartRates as $stat) {
			if ($resting === null || $stat->min < $resting) {
				$resting = $stat->min;
			}
		}

		return new HeadlineFigures(
			todaySteps: $queries->todayStepTotal(),
			latestWeightKg: $weight?->value,
			latestWeightAt: $weight?->at->format('Y-m-d H:i'),
			lastNightSleepMillis: $night?->totalSleepMillis,
			lastNightOn: $night?->night,
			lastNightEfficiency: $night?->efficiency,
			workoutsLast7Days: count($queries->recentWorkouts(7)),
			restingHeartRate: $resting,
		);
	}
}
