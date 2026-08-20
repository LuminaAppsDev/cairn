<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Resolve;

use OCA\Cairn\Reading\Json\Timestamps;
use OCA\Cairn\Reading\Model\HealthMetric;
use OCA\Cairn\Reading\Model\SleepStageReading;
use OCA\Cairn\Reading\Policy\SourcePriorityPolicy;

/**
 * Collapses sleep-stage segments that cover the same window.
 *
 * **The stage is not part of the key.** That looks like a bug and is the whole
 * point: two sources describing the same minutes disagree about what those
 * minutes *were* — one calls them deep sleep, the other calls them awake — and
 * keeping both would count a single stretch twice and invent an awakening that
 * never happened. One window is one span of time, so exactly one segment
 * survives it, and the better-placed source decides which stage it was.
 *
 * A port that adds the stage to the key passes every obvious test and then
 * reports a different number of awakenings than the phone for the same night.
 *
 * The tie-break is source priority, then automatic over self-reported. Ingest
 * time is deliberately absent here, unlike the interval rule: replayed segments
 * are written with fresh identifiers after a crash, so the newest copy carries
 * no more authority than the first.
 */
final class StageResolver {
	public function __construct(
		private readonly SourcePriorityPolicy $policy = new SourcePriorityPolicy(),
	) {
	}

	/**
	 * @param list<SleepStageReading> $segments
	 *
	 * @return list<SleepStageReading> in unspecified order
	 */
	public function resolve(array $segments): array {
		/** @var array<string, SleepStageReading> $best */
		$best = [];

		foreach ($segments as $segment) {
			$key = Timestamps::epochSeconds($segment->start)
				. '|' . Timestamps::epochSeconds($segment->end);

			$incumbent = $best[$key] ?? null;
			if ($incumbent === null || $this->prefers($segment, $incumbent)) {
				$best[$key] = $segment;
			}
		}

		return array_values($best);
	}

	/** Whether `$candidate` should take the window from `$incumbent`. */
	private function prefers(SleepStageReading $candidate, SleepStageReading $incumbent): bool {
		$candidateRank = $this->policy->rank(HealthMetric::Sleep, $candidate->source);
		$incumbentRank = $this->policy->rank(HealthMetric::Sleep, $incumbent->source);
		if ($candidateRank !== $incumbentRank) {
			return $candidateRank < $incumbentRank;
		}

		// Automatic beats hand-entered at equal rank. On a full tie the
		// incumbent stays, so the first seen in read order wins.
		return $this->manualPenalty($candidate) < $this->manualPenalty($incumbent);
	}

	private function manualPenalty(SleepStageReading $segment): int {
		return $segment->source?->isManual() === true ? 1 : 0;
	}
}
