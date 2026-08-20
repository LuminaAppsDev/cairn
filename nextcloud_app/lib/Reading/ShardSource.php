<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading;

use OCA\Cairn\Reading\Model\HealthMetric;

/**
 * Where decoded datapoints come from.
 *
 * One day at a time, because that is the shape of the storage — one `.jsonl`
 * shard per metric per day — and because several queries genuinely work day by
 * day: the latest weight walks backwards until it finds one, and the daily step
 * chart resolves each day separately before summing it.
 *
 * The interface deals in decoded objects and nothing else. No file handle
 * crosses it, which is what lets the whole read path be exercised against a
 * plain directory, or an in-memory fixture, with no Nextcloud anywhere.
 */
interface ShardSource {
	/**
	 * Every usable datapoint for one metric on one local date.
	 *
	 * **Order is significant and must be preserved**: physical line order within
	 * the shard. Every dedup rule resolves an exact tie in favour of the first
	 * reading seen, so read order is part of the format's observable semantics
	 * rather than an implementation detail.
	 *
	 * A missing shard is an empty result, not an error.
	 *
	 * @param string $dayKey local calendar date as `YYYY-MM-DD`
	 *
	 * @return list<object>
	 */
	public function readDay(HealthMetric $metric, string $dayKey): array;
}
