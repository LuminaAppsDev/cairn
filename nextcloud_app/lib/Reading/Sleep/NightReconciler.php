<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Sleep;

use DateTimeZone;
use OCA\Cairn\Reading\Json\Timestamps;
use OCA\Cairn\Reading\Model\NightSleep;
use OCA\Cairn\Reading\Model\SleepEpisode;
use OCA\Cairn\Reading\Model\SleepEpisodeReading;
use OCA\Cairn\Reading\Model\SleepStageReading;
use OCA\Cairn\Reading\Policy\SourcePriorityPolicy;
use OCA\Cairn\Reading\Resolve\StageResolver;

/**
 * Turns a shard's worth of sleep lines into presentable nights.
 *
 * The order is deliberate and each step depends on the last: deduplicate the
 * segments, group what survives into episodes, then describe each episode.
 *
 * **Stage segments are the source of truth.** With no segments there are no
 * nights, even when the folder holds stored `sleep-episode` rollups for the same
 * dates — those are cross-references, and reconstructing a night from one would
 * mean displaying figures the phone never displays. That is a known gap for
 * episode-only sources rather than an oversight (DESIGN.md §4.3).
 */
final class NightReconciler {
	public function __construct(
		private readonly DateTimeZone $display,
		private readonly StageResolver $stages = new StageResolver(),
		private readonly ?SleepEpisodeAggregator $aggregator = null,
	) {
	}

	/**
	 * @param list<SleepStageReading>   $stageReadings
	 * @param list<SleepEpisodeReading> $storedEpisodes
	 *
	 * @return list<NightSleep> in ascending onset order
	 */
	public function reconcile(array $stageReadings, array $storedEpisodes = []): array {
		if ($stageReadings === []) {
			return [];
		}

		$deduped = $this->stages->resolve($stageReadings);
		$aggregator = $this->aggregator ?? new SleepEpisodeAggregator($this->display);

		$nights = [];
		foreach ($aggregator->aggregate($deduped) as $episode) {
			$nights[] = $this->describe($episode, $deduped, $storedEpisodes);
		}

		return $nights;
	}

	/**
	 * @param list<SleepStageReading>   $allStages
	 * @param list<SleepEpisodeReading> $storedEpisodes
	 */
	private function describe(
		SleepEpisode $episode,
		array $allStages,
		array $storedEpisodes,
	): NightSleep {
		$members = array_values(array_filter(
			$allStages,
			static fn (SleepStageReading $s): bool
				=> $s->start >= $episode->start && $s->start <= $episode->end,
		));
		usort($members, static fn (SleepStageReading $a, SleepStageReading $b): int
			=> $a->start <=> $b->start);

		$sources = [];
		$hasWakeMarkers = false;
		foreach ($members as $member) {
			$name = $member->source?->name ?? SourcePriorityPolicy::UNKNOWN_SOURCE;
			$sources[$name] = true;
			if (!$member->stage->isAsleep()) {
				$hasWakeMarkers = true;
			}
		}

		$inBed = Timestamps::elapsedMillis($episode->start, $episode->end);
		// Without wake markers the window is bounded by sleep itself, so time in
		// bed would equal time asleep and efficiency would always be 100% — a
		// number that looks like a measurement and is not one.
		$reportInBed = $hasWakeMarkers && $inBed > 0;

		return new NightSleep(
			night: Timestamps::dayKey($episode->start, $this->display),
			start: $episode->start,
			end: $episode->end,
			totalSleepMillis: $episode->totalSleepMillis,
			awakenings: $episode->awakenings,
			perStageMillis: $episode->perStageMillis,
			isMainSleep: $episode->isMainSleep,
			sources: array_keys($sources),
			stages: $members,
			timeInBedMillis: $reportInBed ? $inBed : null,
			efficiency: $reportInBed ? $episode->totalSleepMillis / $inBed : null,
			storedEpisode: $this->matchStored($episode, $storedEpisodes),
		);
	}

	/**
	 * The stored rollup overlapping this episode, if any.
	 *
	 * Strict overlap: an episode that merely touches another's boundary is a
	 * different sleep, not the same one described twice. First match in read
	 * order wins, which makes shard ordering part of the answer.
	 *
	 * @param list<SleepEpisodeReading> $storedEpisodes
	 */
	private function matchStored(SleepEpisode $episode, array $storedEpisodes): ?SleepEpisodeReading {
		foreach ($storedEpisodes as $stored) {
			if ($stored->start < $episode->end && $stored->end > $episode->start) {
				return $stored;
			}
		}

		return null;
	}
}
