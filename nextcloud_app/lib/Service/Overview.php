<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Service;

/**
 * Everything the landing page needs, in one immutable value.
 *
 * `$hasRoot` is kept separate from an empty `$metrics` list on purpose: "you
 * have not connected the phone app yet" and "your folder is there but empty"
 * need different words, and conflating them produces the kind of error message
 * that sends people looking in the wrong place.
 */
final class Overview {
	/** @param list<MetricOverview> $metrics */
	public function __construct(
		public readonly bool $hasRoot,
		public readonly ?Manifest $manifest,
		public readonly array $metrics,
	) {
	}

	/** Total shard files across every metric. */
	public function totalShards(): int {
		return array_sum(array_map(static fn (MetricOverview $m): int => $m->shardCount, $this->metrics));
	}
}
