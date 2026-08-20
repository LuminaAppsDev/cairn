<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit;

use DateTimeZone;
use OCA\Cairn\Reading\SystemClock;
use PHPUnit\Framework\TestCase;

/**
 * The clock decides what "today" is, and therefore which shard today's steps
 * come from — so reading it in the wrong zone silently shifts a whole day.
 */
final class SystemClockTest extends TestCase {
	public function testReadsNowInTheDisplayZone(): void {
		$zone = new DateTimeZone('Pacific/Kiritimati');
		$now = (new SystemClock($zone))->now();

		self::assertSame($zone->getName(), $now->getTimezone()->getName());
		self::assertEqualsWithDelta(time(), $now->getTimestamp(), 5);
	}

	/**
	 * The instant is the same everywhere; only the wall clock differs. That is
	 * the whole reason the zone is injected rather than read from the process.
	 */
	public function testTheZoneChangesTheDateNotTheInstant(): void {
		$atMidnightUtc = (new SystemClock(new DateTimeZone('UTC')))->now();
		$sameMoment = (new SystemClock(new DateTimeZone('Pacific/Kiritimati')))->now();

		self::assertEqualsWithDelta(
			$atMidnightUtc->getTimestamp(),
			$sameMoment->getTimestamp(),
			5,
		);
		self::assertNotSame(
			$atMidnightUtc->getTimezone()->getName(),
			$sameMoment->getTimezone()->getName(),
		);
	}
}
