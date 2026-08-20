<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Model;

use DateTimeImmutable;

/**
 * One continuous stretch of sleep, recomputed from stage segments.
 *
 * Not to be confused with {@see SleepEpisodeReading}, which is what a *source*
 * claimed. This is what the segments actually say.
 */
final class SleepEpisode {
	/**
	 * @param array<string, int> $perStageMillis stage wire value => milliseconds
	 */
	public function __construct(
		public readonly DateTimeImmutable $start,
		public readonly DateTimeImmutable $end,
		public readonly int $totalSleepMillis,
		public readonly int $awakenings,
		public readonly array $perStageMillis,
		public readonly bool $isMainSleep,
		public readonly ?ReadingSource $source = null,
	) {
	}

	/**
	 * Whether this episode has a real stage breakdown rather than one
	 * undifferentiated block, which decides whether a breakdown chart has
	 * anything to show.
	 */
	public function hasStageBreakdown(): bool {
		foreach (array_keys($this->perStageMillis) as $stage) {
			if ($stage !== SleepStage::Session->value) {
				return true;
			}
		}

		return false;
	}
}
