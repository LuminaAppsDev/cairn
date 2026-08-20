<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Policy;

use OCA\Cairn\Reading\Model\HealthMetric;
use OCA\Cairn\Reading\Model\ReadingSource;

/**
 * Which source to believe when two of them describe the same window.
 *
 * The same metric routinely arrives from several places at once — the phone's
 * own step counter and the band's, say — and naively summing them double-counts
 * (DESIGN.md §4.3). Where the windows collide, the wearable wins: it is strapped
 * to the wrist that did the moving.
 *
 * Matching is by substring on the source name rather than an exact list,
 * because the names are whatever each vendor app happens to report and a fixed
 * roster would go stale on the next device.
 */
final class SourcePriorityPolicy {
	/**
	 * Most-preferred first. A source's rank is the index of the first fragment
	 * its name contains; a source matching nothing ranks below all of them.
	 */
	private const WEARABLES = ['watch', 'wear', 'band', 'fit', 'tracker'];

	/** The name a reading with no usable provenance is ranked under. */
	public const UNKNOWN_SOURCE = 'unknown';

	/**
	 * Weight is deliberately absent: you weigh yourself once, so there is no
	 * competing window to resolve, and a wrist device is not the better scale.
	 *
	 * @return list<string>
	 */
	private function preferredFor(HealthMetric $metric): array {
		return match ($metric) {
			HealthMetric::HeartRate, HealthMetric::Steps,
			HealthMetric::Sleep, HealthMetric::Activity => self::WEARABLES,
			HealthMetric::Weight => [],
		};
	}

	/**
	 * Rank of `$source` for `$metric` — lower wins, unmatched sources tie last.
	 *
	 * With no preferences for a metric every source ranks 0, which makes the
	 * caller's later tie-break the only thing that decides.
	 */
	public function rank(HealthMetric $metric, ?ReadingSource $source): int {
		$order = $this->preferredFor($metric);
		// mb_strtolower, not strtolower: the latter is byte-wise and would leave
		// a non-ASCII device name unmatched depending on the server's locale.
		$name = mb_strtolower($source?->name ?? self::UNKNOWN_SOURCE, 'UTF-8');

		foreach ($order as $index => $fragment) {
			if (str_contains($name, $fragment)) {
				return $index;
			}
		}

		return count($order);
	}
}
