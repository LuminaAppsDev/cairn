<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Model;

use DateTimeImmutable;

/**
 * A stored `omh:sleep-episode` rollup, as written by the phone.
 *
 * Cross-reference only. Every figure a reader displays is recomputed from the
 * stage segments, so these values are carried but never rendered — see
 * {@see \OCA\Cairn\Reading\Sleep\NightReconciler}. Rendering them instead would
 * be the easiest possible way for the two frontends to disagree, because the
 * stored rollup and the recomputation can differ legitimately.
 */
final class SleepEpisodeReading {
	public function __construct(
		public readonly DateTimeImmutable $start,
		public readonly DateTimeImmutable $end,
		public readonly int $totalSleepMillis,
		public readonly bool $isMainSleep,
		public readonly int $awakenings,
		public readonly ?int $lightMillis = null,
		public readonly ?int $deepMillis = null,
		public readonly ?int $remMillis = null,
		public readonly ?ReadingSource $source = null,
	) {
	}
}
