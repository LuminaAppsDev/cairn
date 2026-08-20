<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Support;

use DateTimeImmutable;
use DateTimeZone;
use OCA\Cairn\Reading\Model\IntervalReading;
use OCA\Cairn\Reading\Model\ReadingSource;
use OCA\Cairn\Reading\Model\ScalarReading;
use OCA\Cairn\Reading\Model\SleepStage;
use OCA\Cairn\Reading\Model\SleepStageReading;

/**
 * Terse constructors for readings, so a test reads as the situation it
 * describes rather than as a wall of arguments.
 */
final class Readings {
	public const ZONE = 'Europe/Berlin';

	public static function zone(): DateTimeZone {
		return new DateTimeZone(self::ZONE);
	}

	/** A wall-clock instant on 2026-08-20 unless a full date is given. */
	public static function at(string $time): DateTimeImmutable {
		$value = str_contains($time, '-') ? $time : "2026-08-20 {$time}";

		return new DateTimeImmutable($value, self::zone());
	}

	public static function source(string $name, string $modality = 'sensed'): ReadingSource {
		return new ReadingSource($name, $modality);
	}

	public static function scalar(
		float $value,
		string $at,
		?string $source = null,
		?string $ingestedAt = null,
		string $modality = 'sensed',
		string $unit = 'kg',
	): ScalarReading {
		return new ScalarReading(
			value: $value,
			unit: $unit,
			at: self::at($at),
			source: $source === null ? null : self::source($source, $modality),
			ingestedAt: $ingestedAt === null ? null : self::at($ingestedAt),
		);
	}

	public static function interval(
		float $value,
		string $start,
		string $end,
		?string $source = null,
		?string $ingestedAt = null,
	): IntervalReading {
		return new IntervalReading(
			value: $value,
			unit: 'steps',
			start: self::at($start),
			end: self::at($end),
			source: $source === null ? null : self::source($source),
			ingestedAt: $ingestedAt === null ? null : self::at($ingestedAt),
		);
	}

	public static function stage(
		SleepStage $stage,
		string $start,
		string $end,
		?string $source = null,
		string $modality = 'sensed',
	): SleepStageReading {
		return new SleepStageReading(
			stage: $stage,
			start: self::at($start),
			end: self::at($end),
			source: $source === null ? null : self::source($source, $modality),
		);
	}
}
