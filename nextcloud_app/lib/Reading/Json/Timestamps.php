<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Json;

use DateTimeImmutable;
use DateTimeZone;

/**
 * Parsing and bucketing of the timestamps in an OMH datapoint.
 *
 * Two details carry most of the risk of the whole port.
 *
 * **Parsing must reject non-timestamps.** The mobile reader uses
 * `DateTime.tryParse`, which returns null for anything that is not ISO 8601.
 * PHP's `new DateTimeImmutable()` is a natural-language parser: it accepts
 * `now`, `+1 day`, `tomorrow`, and reads a bare `62` as a time. Feeding it an
 * unvalidated field would silently invent readings, so a strict pattern gates
 * every value before it is handed over.
 *
 * **The display timezone is a single, explicit choice.** The phone writes
 * wall-clock times with its own offset, and the mobile reader converts them to
 * the device's local zone before deciding which day a reading belongs to.
 * A server rendering the same files has no device zone, so one is injected —
 * the Nextcloud user's own. It is applied in all three places it matters: to
 * timestamps that carry no offset at all, to day bucketing, and to "today".
 * Using the server default in any one of them would make the web app disagree
 * with the phone about the same file, which DESIGN.md §4.3 forbids.
 */
final class Timestamps {
	/**
	 * ISO 8601 as the mobile reader accepts it: a date, optionally a time, and
	 * optionally a zone designator. Deliberately anchored with `\z` rather than
	 * `$`, which in PCRE also matches before a trailing newline.
	 */
	private const ISO_8601 = '/^\d{4,6}-\d{2}-\d{2}'
		. '(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?)?'
		. '(?:Z|[+-]\d{2}(?::?\d{2})?)?\z/i';

	/**
	 * Parse an OMH timestamp into `$display`, or `null` if it is not one.
	 *
	 * A value with an offset (`+02:00`, `Z`) denotes an instant and is converted
	 * into the display zone. A value without one is read *as* display-zone wall
	 * clock, which is what the mobile reader does with its device zone — hence
	 * passing `$display` to the constructor, where PHP applies it only when the
	 * string carries no offset of its own.
	 */
	public static function parse(?string $value, DateTimeZone $display): ?DateTimeImmutable {
		if ($value === null || preg_match(self::ISO_8601, $value) !== 1) {
			return null;
		}

		try {
			$parsed = new DateTimeImmutable($value, $display);
		} catch (\Exception) {
			// The pattern matched but the values did not exist — month 19, say.
			return null;
		}

		return $parsed->setTimezone($display);
	}

	/**
	 * Whole seconds since the epoch — the identity used to decide whether two
	 * readings describe the same instant or the same window.
	 */
	public static function epochSeconds(DateTimeImmutable $at): int {
		return $at->getTimestamp();
	}

	/**
	 * Whole milliseconds between two instants.
	 *
	 * Absolute elapsed time, matching Dart's `DateTime.difference`. Integer
	 * milliseconds rather than `DateInterval` for two reasons: a `DateInterval`
	 * has no single total-magnitude accessor (its `days` is populated only by
	 * `diff`, and there is nothing for milliseconds at all), and Dart's
	 * `Duration` is an integer count, so an integer here compares exactly with
	 * `===` instead of through float tolerance. Milliseconds specifically
	 * because OMH writes durations as decimal minutes that round to the
	 * millisecond.
	 *
	 * Note this is *not* a fix for a DST bug in `DateTime::diff` — that method
	 * measures elapsed time correctly across a fall-back, verified in the tests.
	 * The choice here is about representation, not correctness.
	 */
	public static function elapsedMillis(DateTimeImmutable $from, DateTimeImmutable $to): int {
		return ($to->getTimestamp() - $from->getTimestamp()) * 1000;
	}

	/** Minutes-as-decimal (as OMH writes durations) to whole milliseconds. */
	public static function minutesToMillis(float $minutes): int {
		// Half away from zero, matching Dart's `.round()`.
		return (int)round($minutes * 60000.0);
	}

	/** The local calendar date a reading falls on, as `YYYY-MM-DD`. */
	public static function dayKey(DateTimeImmutable $at, DateTimeZone $display): string {
		return $at->setTimezone($display)->format('Y-m-d');
	}

	/** Local midnight starting `$dayKey`. */
	public static function startOfDay(string $dayKey, DateTimeZone $display): DateTimeImmutable {
		return new DateTimeImmutable($dayKey . ' 00:00:00', $display);
	}
}
