<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Resolve;

use OCA\Cairn\Reading\Resolve\LatestWins;
use OCA\Cairn\Tests\Support\Readings;
use PHPUnit\Framework\TestCase;

/**
 * The tie-break every dedup rule shares, tested where it is defined rather than
 * only through the two resolvers that use it.
 */
final class LatestWinsTest extends TestCase {
	public function testALaterIngestWins(): void {
		self::assertTrue(LatestWins::isNewer(Readings::at('09:02'), Readings::at('06:25')));
		self::assertFalse(LatestWins::isNewer(Readings::at('06:25'), Readings::at('09:02')));
	}

	/**
	 * Strictly later. On an exact tie the incumbent stays, which makes the
	 * winner the first seen in read order — and that ordering therefore part of
	 * the format's observable semantics, not an implementation detail.
	 */
	public function testAnExactTieKeepsTheIncumbent(): void {
		self::assertFalse(LatestWins::isNewer(Readings::at('09:02'), Readings::at('09:02')));
	}

	/**
	 * An unknown ingest time never displaces anything. A line whose header lost
	 * its `creation_date_time` carries no evidence that it is the newer one, so
	 * "keep what we have" is the only answer that does not depend on the order
	 * the files happened to be read in.
	 */
	public function testAnUnknownTimeNeverDisplaces(): void {
		self::assertFalse(LatestWins::isNewer(null, Readings::at('06:25')));
		self::assertFalse(LatestWins::isNewer(null, null));
	}

	/** A dated reading always beats an undated one, whichever arrives first. */
	public function testADatedReadingBeatsAnUndatedOne(): void {
		self::assertTrue(LatestWins::isNewer(Readings::at('06:25'), null));
	}
}
