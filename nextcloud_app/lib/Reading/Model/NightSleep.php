<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Model;

use DateTimeImmutable;

/**
 * A night as it is presented: one episode, plus the context around it.
 *
 * Every measured figure here is recomputed from stage segments. `$storedEpisode`
 * is what the source claimed for the same window and is carried for comparison
 * only — never rendered — because the phone recomputes too, and showing the
 * stored value on one frontend and the recomputed value on the other is exactly
 * the disagreement DESIGN.md §4.3 rules out.
 */
final class NightSleep {
	/**
	 * @param array<string, int>      $perStageMillis
	 * @param list<string>            $sources
	 * @param list<SleepStageReading> $stages
	 */
	public function __construct(
		/** Local calendar date of the episode's onset, as `YYYY-MM-DD`. */
		public readonly string $night,
		public readonly DateTimeImmutable $start,
		public readonly DateTimeImmutable $end,
		public readonly int $totalSleepMillis,
		public readonly int $awakenings,
		public readonly array $perStageMillis,
		public readonly bool $isMainSleep,
		public readonly array $sources,
		public readonly array $stages,
		/**
		 * Time in bed, or `null` when the source recorded no wake markers at
		 * all. Null rather than a guess: without them the window's edges are
		 * onset and final waking, so "in bed" and "asleep" would be the same
		 * number and efficiency would be a meaningless 100%.
		 */
		public readonly ?int $timeInBedMillis = null,
		/** Sleep as a fraction of time in bed, 0..1, or `null`. */
		public readonly ?float $efficiency = null,
		public readonly ?SleepEpisodeReading $storedEpisode = null,
	) {
	}

	/** Whether a stage breakdown chart has anything to show. */
	public function hasStageBreakdown(): bool {
		foreach (array_keys($this->perStageMillis) as $stage) {
			if ($stage !== SleepStage::Session->value) {
				return true;
			}
		}

		return false;
	}
}
