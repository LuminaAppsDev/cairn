<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Service;

/**
 * What one metric's folder looks like on disk.
 *
 * Enough to prove the app is really reading the files — how many shards there
 * are, the range they span, and what the newest one actually decodes to — without
 * yet interpreting a single reading. The interpretation layer lands with the
 * read-path port (DESIGN.md §4.3).
 */
final class MetricOverview {
	public function __construct(
		public readonly HealthMetric $metric,
		public readonly int $shardCount,
		public readonly ?string $firstDay,
		public readonly ?string $lastDay,
		public readonly int $newestDatapoints,
		public readonly int $newestSkippedLines,
	) {
	}
}
