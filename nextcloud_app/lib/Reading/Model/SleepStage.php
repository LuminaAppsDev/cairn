<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Model;

/**
 * The sleep stages Cairn records, and their on-disk spellings.
 *
 * These strings are part of the `cairn:sleep-stage` schema (DESIGN.md §5.2), so
 * they are format, not presentation. An unrecognised value is not mapped to a
 * fallback: the reading is dropped, because guessing which stage a future
 * writer meant would put invented sleep on someone's dashboard.
 */
enum SleepStage: string {
	case Awake = 'awake';
	case Light = 'light';
	case Deep = 'deep';
	case Rem = 'rem';
	case AsleepUnspecified = 'asleep_unspecified';
	case InBed = 'in_bed';
	case OutOfBed = 'out_of_bed';
	case Session = 'session';

	/** The stage for an on-disk value, or `null` if it is not one we know. */
	public static function fromWire(?string $wire): ?self {
		return $wire === null ? null : self::tryFrom($wire);
	}

	/**
	 * Whether this stage counts as actually asleep.
	 *
	 * `in_bed` and `out_of_bed` are position, not sleep, and `awake` is the
	 * explicit opposite. `session` counts: it is the whole-episode marker some
	 * sources emit instead of a stage breakdown, and a night made only of
	 * sessions still has to report a duration.
	 */
	public function isAsleep(): bool {
		return match ($this) {
			self::Light, self::Deep, self::Rem, self::AsleepUnspecified, self::Session => true,
			self::Awake, self::InBed, self::OutOfBed => false,
		};
	}
}
