<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Sleep;

use DateTimeImmutable;
use DateTimeZone;
use OCA\Cairn\Reading\Json\Timestamps;
use OCA\Cairn\Reading\Model\SleepEpisode;
use OCA\Cairn\Reading\Model\SleepStage;
use OCA\Cairn\Reading\Model\SleepStageReading;

/**
 * Groups sleep-stage segments into episodes and measures each one.
 *
 * Health stores hand out a night as a pile of segments with no notion of where
 * one sleep ends and the next begins. Grouping them is the reader's job, and the
 * rule is a gap tolerance: a break longer than an hour starts a new episode, a
 * shorter one is just a trip to the bathroom.
 */
final class SleepEpisodeAggregator {
	/** A break longer than this starts a new episode. */
	public const GAP_TOLERANCE_MILLIS = 60 * 60 * 1000;

	public function __construct(
		private readonly DateTimeZone $display,
		private readonly int $gapToleranceMillis = self::GAP_TOLERANCE_MILLIS,
	) {
	}

	/**
	 * @param list<SleepStageReading> $segments already deduplicated
	 *
	 * @return list<SleepEpisode> in ascending onset order
	 */
	public function aggregate(array $segments): array {
		if ($segments === []) {
			return [];
		}

		$sorted = $segments;
		usort($sorted, static fn (SleepStageReading $a, SleepStageReading $b): int
			=> $a->start <=> $b->start);

		/** @var list<list<SleepStageReading>> $groups */
		$groups = [];
		$current = [$sorted[0]];
		$groupEnd = $sorted[0]->end;

		foreach (array_slice($sorted, 1) as $segment) {
			// Measured against the running maximum end, not the previous
			// segment's: sources emit overlapping segments (a whole-night
			// `session` alongside its own sub-stages), and comparing against the
			// last one seen would split a night wherever a long segment was
			// followed by a short one that started earlier than it ended.
			$gap = Timestamps::elapsedMillis($groupEnd, $segment->start);
			// Strictly greater: a gap of exactly the tolerance stays together.
			if ($gap > $this->gapToleranceMillis) {
				$groups[] = $current;
				$current = [];
			}
			$current[] = $segment;
			if ($segment->end > $groupEnd) {
				$groupEnd = $segment->end;
			}
		}
		$groups[] = $current;

		return $this->measure($groups);
	}

	/**
	 * @param list<list<SleepStageReading>> $groups
	 *
	 * @return list<SleepEpisode>
	 */
	private function measure(array $groups): array {
		/** @var list<array{start: DateTimeImmutable, end: DateTimeImmutable, total: int, awakenings: int, stages: array<string, int>, source: ?\OCA\Cairn\Reading\Model\ReadingSource}> $stats */
		$stats = [];
		/** @var array<string, int> $bestPerNight */
		$bestPerNight = [];

		foreach ($groups as $group) {
			$start = $group[0]->start;
			$end = $group[0]->end;
			$awakenings = 0;
			/** @var array<string, int> $stages */
			$stages = [];

			foreach ($group as $segment) {
				if ($segment->end > $end) {
					$end = $segment->end;
				}
				if ($segment->stage === SleepStage::Awake) {
					// Counted per segment, not per merged interval: two adjacent
					// awake spans are two awakenings. And specifically `awake` —
					// `in_bed` and `out_of_bed` are position, not waking up.
					$awakenings++;
				}
				$key = $segment->stage->value;
				// A plain sum per stage. Overlapping same-stage segments do
				// double-count here, which is why the breakdown is presented as
				// a proportion and total sleep is computed separately.
				$stages[$key] = ($stages[$key] ?? 0) + $segment->durationMillis();
			}

			$total = $this->asleepUnionMillis($group);
			$night = Timestamps::dayKey($start, $this->display);
			if (!isset($bestPerNight[$night]) || $total > $bestPerNight[$night]) {
				$bestPerNight[$night] = $total;
			}

			$stats[] = [
				'start' => $start,
				'end' => $end,
				'total' => $total,
				'awakenings' => $awakenings,
				'stages' => $stages,
				'source' => $group[0]->source,
			];
		}

		$episodes = [];
		foreach ($stats as $stat) {
			$night = Timestamps::dayKey($stat['start'], $this->display);
			$episodes[] = new SleepEpisode(
				start: $stat['start'],
				end: $stat['end'],
				totalSleepMillis: $stat['total'],
				awakenings: $stat['awakenings'],
				perStageMillis: $stat['stages'],
				// The night's longest sleep is the main one. An exact tie flags
				// both, which is honest: nothing in the data breaks it.
				isMainSleep: $stat['total'] > 0 && $stat['total'] === $bestPerNight[$night],
				source: $stat['source'],
			);
		}

		return $episodes;
	}

	/**
	 * Total time actually asleep: the **union** of the asleep intervals.
	 *
	 * A union rather than a sum, because sources overlap their own segments —
	 * Samsung emits a whole-night `session` alongside the light/deep/rem
	 * breakdown of the same minutes. Summing those reports eleven hours of sleep
	 * for a seven-hour night.
	 *
	 * @param list<SleepStageReading> $group
	 */
	private function asleepUnionMillis(array $group): int {
		$asleep = array_values(array_filter(
			$group,
			static fn (SleepStageReading $s): bool => $s->stage->isAsleep(),
		));
		if ($asleep === []) {
			return 0;
		}
		usort($asleep, static fn (SleepStageReading $a, SleepStageReading $b): int
			=> $a->start <=> $b->start);

		$total = 0;
		$mergeStart = $asleep[0]->start;
		$mergeEnd = $asleep[0]->end;

		foreach (array_slice($asleep, 1) as $segment) {
			// Touching intervals merge: 01:00-02:00 and 02:00-03:00 are two
			// hours of continuous sleep, not two separate stretches.
			if ($segment->start <= $mergeEnd) {
				if ($segment->end > $mergeEnd) {
					$mergeEnd = $segment->end;
				}
				continue;
			}
			$total += Timestamps::elapsedMillis($mergeStart, $mergeEnd);
			$mergeStart = $segment->start;
			$mergeEnd = $segment->end;
		}

		return $total + Timestamps::elapsedMillis($mergeStart, $mergeEnd);
	}
}
