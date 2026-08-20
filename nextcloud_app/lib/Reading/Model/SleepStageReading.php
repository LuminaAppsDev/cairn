<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Model;

use DateTimeImmutable;
use OCA\Cairn\Reading\Json\Timestamps;

/** One `cairn:sleep-stage` segment: a stage held over a window. */
final class SleepStageReading {
	public function __construct(
		public readonly SleepStage $stage,
		public readonly DateTimeImmutable $start,
		public readonly DateTimeImmutable $end,
		public readonly ?ReadingSource $source = null,
	) {
	}

	/** Segment length in milliseconds. */
	public function durationMillis(): int {
		return Timestamps::elapsedMillis($this->start, $this->end);
	}
}
