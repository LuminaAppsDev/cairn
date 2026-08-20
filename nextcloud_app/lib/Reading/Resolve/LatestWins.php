<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Resolve;

use DateTimeImmutable;

/**
 * The tie-break every dedup rule shares: which of two lines was written last.
 *
 * An unknown ingest time never displaces anything. That asymmetry is deliberate
 * — a line whose header lost its `creation_date_time` carries no evidence that
 * it is the newer one, so "keep what we already have" is the only answer that
 * does not depend on which order the files happened to be read in.
 */
final class LatestWins {
	/**
	 * Whether `$candidate` was ingested strictly after `$incumbent`.
	 *
	 * Strictly: on an exact tie the incumbent stays, which makes the winner the
	 * first one seen in read order — day-ascending, then line order — and that
	 * ordering is therefore part of the format's observable semantics, not an
	 * implementation detail.
	 */
	public static function isNewer(?DateTimeImmutable $candidate, ?DateTimeImmutable $incumbent): bool {
		if ($candidate === null) {
			return false;
		}

		return $incumbent === null || $candidate > $incumbent;
	}
}
