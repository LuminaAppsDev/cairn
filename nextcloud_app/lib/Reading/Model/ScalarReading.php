<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Model;

use DateTimeImmutable;

/**
 * A point-in-time measurement: heart rate, body weight.
 *
 * `$ingestedAt` is the OMH header's `creation_date_time` — when Cairn wrote the
 * line, not when the body produced the number. It is what resolves an in-place
 * correction in the source health app: append-only files forbid rewriting the
 * original, so both versions sit on disk and the later-ingested one wins
 * (DESIGN.md §4.3). A reading whose header lacked the field carries `null` and
 * can never displace anything.
 */
final class ScalarReading {
	public function __construct(
		public readonly float $value,
		/** Taken from the schema body, never invented, never converted. */
		public readonly string $unit,
		public readonly DateTimeImmutable $at,
		public readonly ?ReadingSource $source = null,
		public readonly ?DateTimeImmutable $ingestedAt = null,
	) {
	}
}
