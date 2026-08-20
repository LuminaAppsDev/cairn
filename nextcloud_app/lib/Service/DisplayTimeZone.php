<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Service;

use DateTimeZone;
use OCP\IDateTimeZone;

/**
 * The one timezone every read decision is made in.
 *
 * The phone writes wall-clock times with its own offset and reads them back in
 * the device's zone, which is what decides the day a reading belongs to. A
 * server has no device zone, so one has to be chosen — and the only choice that
 * keeps the two frontends agreeing about the same files is the Nextcloud user's
 * own, which is what `IDateTimeZone` resolves (browser-detected, falling back to
 * the instance default).
 *
 * Anything else — the server's default, UTC, a constant — would put a late
 * evening reading on a different day here than on the phone, which DESIGN.md
 * §4.3 rules out. `date_default_timezone_set()` is never called: the zone is
 * passed explicitly so nothing can read it implicitly and get a different answer.
 */
final class DisplayTimeZone {
	public function __construct(
		private readonly IDateTimeZone $dateTimeZone,
	) {
	}

	public function get(): DateTimeZone {
		return $this->dateTimeZone->getTimeZone();
	}
}
