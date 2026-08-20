<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Service;

use DateTimeZone;
use OCA\Cairn\Service\DisplayTimeZone;
use OCP\IDateTimeZone;
use PHPUnit\Framework\TestCase;

/**
 * The one timezone every read decision is made in.
 *
 * The phone reads its files in the device's zone, and that is what decides
 * which day a reading belongs to. A server has none, so one is chosen — the
 * user's own. Anything else would put a late-evening reading on a different day
 * here than on the phone, which DESIGN.md §4.3 rules out.
 */
final class DisplayTimeZoneTest extends TestCase {
	public function testUsesTheUsersOwnZone(): void {
		$source = $this->createStub(IDateTimeZone::class);
		$source->method('getTimeZone')->willReturn(new DateTimeZone('Europe/Berlin'));

		self::assertSame('Europe/Berlin', (new DisplayTimeZone($source))->get()->getName());
	}

	/**
	 * Asked each time rather than cached. A user can change their zone, and a
	 * stale one would silently file readings under the wrong day.
	 */
	public function testAsksEveryTime(): void {
		$source = $this->createMock(IDateTimeZone::class);
		$source->expects(self::exactly(2))
			->method('getTimeZone')
			->willReturn(new DateTimeZone('UTC'));

		$zone = new DisplayTimeZone($source);
		$zone->get();
		$zone->get();
	}
}
