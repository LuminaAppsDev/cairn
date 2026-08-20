<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Resolve;

use OCA\Cairn\Reading\Json\Timestamps;
use OCA\Cairn\Reading\Model\HealthMetric;
use OCA\Cairn\Reading\Model\IntervalReading;
use OCA\Cairn\Reading\Policy\SourcePriorityPolicy;

/**
 * Collapses step readings to one per window, so the survivors can be summed.
 *
 * Two different things arrive as "steps" and only one of them may be added up.
 * Genuine per-interval deltas have distinct windows and are summed. A source
 * re-reporting a **cumulative total** in a fixed window does not: Samsung Health
 * exposes the day's steps as a single whole-day record whose value climbs
 * through the day, so every sync appends another snapshot with an identical
 * window. Summing those would wildly over-count; keeping the first would pin a
 * stale figure. The newest snapshot is the current total (DESIGN.md §4.3).
 *
 * The window alone is the key — the source is deliberately *not* part of it, so
 * two devices reporting the same window collapse to one reading rather than
 * double-counting. Which one survives is decided by source priority first and
 * ingest time only on a tie, and that order matters: reversing it would let a
 * phone's later sync displace the wearable's better number.
 */
final class IntervalResolver {
	public function __construct(
		private readonly SourcePriorityPolicy $policy = new SourcePriorityPolicy(),
	) {
	}

	/**
	 * @param list<IntervalReading> $readings
	 *
	 * @return list<IntervalReading> in unspecified order; callers sum or sort
	 */
	public function resolve(array $readings, HealthMetric $metric = HealthMetric::Steps): array {
		/** @var array<string, IntervalReading> $best */
		$best = [];

		foreach ($readings as $reading) {
			// Two integers joined by a character neither can contain, so this
			// key cannot collide the way a free-text one could.
			$key = Timestamps::epochSeconds($reading->start)
				. '|' . Timestamps::epochSeconds($reading->end);

			$incumbent = $best[$key] ?? null;
			if ($incumbent === null || $this->prefers($metric, $reading, $incumbent)) {
				$best[$key] = $reading;
			}
		}

		return array_values($best);
	}

	/** Whether `$candidate` should take the window from `$incumbent`. */
	private function prefers(
		HealthMetric $metric,
		IntervalReading $candidate,
		IntervalReading $incumbent,
	): bool {
		$candidateRank = $this->policy->rank($metric, $candidate->source);
		$incumbentRank = $this->policy->rank($metric, $incumbent->source);
		if ($candidateRank !== $incumbentRank) {
			return $candidateRank < $incumbentRank;
		}

		return LatestWins::isNewer($candidate->ingestedAt, $incumbent->ingestedAt);
	}
}
