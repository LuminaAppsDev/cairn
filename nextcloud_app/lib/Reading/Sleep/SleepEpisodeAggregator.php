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

			$total = $this->asleepMillis($group);
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
	 * Total time actually asleep: sleep intervals, minus any wakefulness inside
	 * them.
	 *
	 * A union rather than a sum, because sources overlap their own segments —
	 * Samsung emits a whole-night `session` alongside the light/deep/rem
	 * breakdown of the same minutes. Summing those reports eleven hours of sleep
	 * for a seven-hour night.
	 *
	 * And a *difference* rather than only a union, because that same whole-night
	 * `session` also spans the awake stretches inside it. Counting the union
	 * alone reported a night with twenty-six awakenings as six hours sixteen of
	 * unbroken sleep at 100% efficiency; subtracting the wake intervals gives
	 * five hours thirty at 88%, which is what the stage segments actually say.
	 *
	 * The rule is deliberately a set operation rather than a heuristic about
	 * which stages to ignore: time asleep is time inside a sleep interval and
	 * not inside a wake interval. That needs no special case for sources that
	 * emit a session marker, and none for sources that do not.
	 *
	 * @param list<SleepStageReading> $group
	 */
	private function asleepMillis(array $group): int {
		$asleep = $this->merge(array_filter(
			$group,
			static fn (SleepStageReading $s): bool => $s->stage->isAsleep(),
		));
		$awake = $this->merge(array_filter(
			$group,
			static fn (SleepStageReading $s): bool => $s->stage->isAwake(),
		));

		$total = 0;
		foreach ($asleep as [$start, $end]) {
			$cursor = $start;
			foreach ($awake as [$wakeStart, $wakeEnd]) {
				if ($wakeEnd <= $cursor) {
					continue;
				}
				if ($wakeStart >= $end) {
					break;
				}
				if ($wakeStart > $cursor) {
					$total += Timestamps::elapsedMillis($cursor, $wakeStart);
				}
				$cursor = $wakeEnd > $cursor ? $wakeEnd : $cursor;
				if ($cursor >= $end) {
					break;
				}
			}
			if ($cursor < $end) {
				$total += Timestamps::elapsedMillis($cursor, $end);
			}
		}

		return $total;
	}

	/**
	 * Collapse segments into non-overlapping intervals, ascending.
	 *
	 * Touching intervals merge: 01:00–02:00 followed by 02:00–03:00 is two hours
	 * of one thing, not two separate stretches.
	 *
	 * @param iterable<SleepStageReading> $segments
	 *
	 * @return list<array{\DateTimeImmutable, \DateTimeImmutable}>
	 */
	private function merge(iterable $segments): array {
		$intervals = [];
		foreach ($segments as $segment) {
			$intervals[] = [$segment->start, $segment->end];
		}
		if ($intervals === []) {
			return [];
		}
		usort($intervals, static fn (array $a, array $b): int => $a[0] <=> $b[0]);

		$merged = [];
		[$start, $end] = $intervals[0];
		foreach (array_slice($intervals, 1) as [$next, $nextEnd]) {
			if ($next <= $end) {
				if ($nextEnd > $end) {
					$end = $nextEnd;
				}
				continue;
			}
			$merged[] = [$start, $end];
			$start = $next;
			$end = $nextEnd;
		}
		$merged[] = [$start, $end];

		return $merged;
	}
}
