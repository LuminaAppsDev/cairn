<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Resolve;

use OCA\Cairn\Reading\Json\Timestamps;
use OCA\Cairn\Reading\Model\ScalarReading;

/**
 * Collapses scalar readings that describe the *same measurement*.
 *
 * Same source, same instant — that is one measurement, however many lines
 * describe it. The common cause is an in-place edit in the health app, most
 * often a re-typed manual weight: append-only files forbid rewriting the
 * original, so both values coexist and the later-ingested one is shown while
 * the earlier stays on disk as an audit trail (DESIGN.md §4.3).
 *
 * Readings from *different* sources at the same instant are two measurements
 * and are both kept. Readings with no parseable provenance share one bucket:
 * provenance is the only identity available, so two unattributed readings of
 * the same instant are treated as one.
 */
final class ScalarResolver {
	/**
	 * @param list<ScalarReading> $readings
	 *
	 * @return list<ScalarReading> in unspecified order; callers sort
	 */
	public function resolve(array $readings): array {
		/** @var array<string, array<int, ScalarReading>> $best */
		$best = [];

		foreach ($readings as $reading) {
			// Nested by source name and then by instant, rather than joined into
			// one delimited string. A source name is free text — it can contain
			// whatever character were chosen as a separator — and a collision
			// there would silently merge two genuinely distinct measurements.
			$name = $reading->source?->name ?? '';
			$second = Timestamps::epochSeconds($reading->at);

			$incumbent = $best[$name][$second] ?? null;
			if ($incumbent === null
				|| LatestWins::isNewer($reading->ingestedAt, $incumbent->ingestedAt)) {
				$best[$name][$second] = $reading;
			}
		}

		$out = [];
		foreach ($best as $bySecond) {
			foreach ($bySecond as $reading) {
				$out[] = $reading;
			}
		}

		return $out;
	}
}
