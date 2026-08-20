<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Support;

use DateTimeImmutable;
use OCA\Cairn\Reading\Clock;

/** A clock stopped at a chosen instant. */
final class FixedClock implements Clock {
	public function __construct(
		private readonly DateTimeImmutable $now,
	) {
	}

	public static function at(string $when): self {
		return new self(new DateTimeImmutable($when, Readings::zone()));
	}

	public function now(): DateTimeImmutable {
		return $this->now;
	}
}
