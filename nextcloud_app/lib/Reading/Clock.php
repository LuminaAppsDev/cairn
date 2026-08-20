<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading;

use DateTimeImmutable;

/**
 * Where "now" comes from.
 *
 * Injected rather than read from the system, because almost every query here is
 * defined relative to today — "the last 14 days", "today's steps" — and a test
 * that cannot fix the date can only assert vague things about whatever day it
 * happens to run on.
 */
interface Clock {
	public function now(): DateTimeImmutable;
}
