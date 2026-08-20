<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading;

use DateTimeImmutable;
use DateTimeZone;

/** The real clock, reading the wall clock in the display timezone. */
final class SystemClock implements Clock {
	public function __construct(
		private readonly DateTimeZone $display,
	) {
	}

	public function now(): DateTimeImmutable {
		return new DateTimeImmutable('now', $this->display);
	}
}
