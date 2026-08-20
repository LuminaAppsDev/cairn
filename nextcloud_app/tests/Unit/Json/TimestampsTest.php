<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Json;

use DateTimeImmutable;
use DateTimeZone;
use OCA\Cairn\Reading\Json\Timestamps;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

final class TimestampsTest extends TestCase {
	private DateTimeZone $berlin;

	protected function setUp(): void {
		// A zone with DST, deliberately: the interesting failures all live at
		// the two boundaries, and a fixed-offset zone hides every one of them.
		$this->berlin = new DateTimeZone('Europe/Berlin');
	}

	/** @return array<string, array{string}> */
	public static function notTimestamps(): array {
		return [
			'relative phrase' => ['now'],
			'relative offset' => ['+1 day'],
			'tomorrow' => ['tomorrow'],
			'bare number' => ['62'],
			'empty' => [''],
			'whitespace' => ['   '],
			'prose' => ['not-a-timestamp'],
			'partial date' => ['2026-08'],
			'us format' => ['08/20/2026'],
			'trailing junk' => ['2026-08-20T10:00:00+02:00 and more'],
			'leading junk' => ['at 2026-08-20T10:00:00+02:00'],
			'newline suffix' => ["2026-08-20T10:00:00+02:00\n"],
		];
	}

	/**
	 * PHP's date constructor is a natural-language parser: unguarded, every one
	 * of these produces a real DateTimeImmutable, which would mean inventing
	 * readings the phone never shows.
	 */
	#[DataProvider('notTimestamps')]
	public function testRejectsAnythingThatIsNotIso8601(string $value): void {
		$this->assertNull(Timestamps::parse($value, $this->berlin));
	}

	public function testRejectsImpossibleDatesThatMatchTheShape(): void {
		$this->assertNull(Timestamps::parse('2026-19-40T10:00:00+02:00', $this->berlin));
		$this->assertNull(Timestamps::parse('2026-02-30T99:99:99+02:00', $this->berlin));
	}

	public function testNullIsNotAnError(): void {
		$this->assertNull(Timestamps::parse(null, $this->berlin));
	}

	/** @return array<string, array{string}> */
	public static function acceptedForms(): array {
		return [
			'what Cairn writes' => ['2026-08-20T06:19:41+02:00'],
			'utc designator' => ['2026-08-20T04:19:41Z'],
			'offset without colon' => ['2026-08-20T06:19:41+0200'],
			'offset hours only' => ['2026-08-20T06:19:41+02'],
			'fractional seconds' => ['2026-08-20T06:19:41.123+02:00'],
			'minutes only' => ['2026-08-20T06:19+02:00'],
			'date only' => ['2026-08-20'],
			'space separator' => ['2026-08-20 06:19:41+02:00'],
		];
	}

	#[DataProvider('acceptedForms')]
	public function testAcceptsTheIsoFormsTheMobileReaderAccepts(string $value): void {
		$this->assertInstanceOf(DateTimeImmutable::class, Timestamps::parse($value, $this->berlin));
	}

	/** An offset denotes an instant, and is converted into the display zone. */
	public function testAnOffsetIsAnInstantConvertedToTheDisplayZone(): void {
		$parsed = Timestamps::parse('2026-08-20T04:19:41Z', $this->berlin);
		$this->assertNotNull($parsed);
		// 04:19:41 UTC is 06:19:41 in Berlin in August (CEST, +02:00).
		$this->assertSame('2026-08-20 06:19:41 +02:00', $parsed->format('Y-m-d H:i:s P'));
	}

	/**
	 * No offset means wall clock in the reader's zone — what the mobile reader
	 * does with the device zone. Reading it as UTC instead would shift a whole
	 * night into the wrong day.
	 */
	public function testAnOffsetlessValueIsReadAsDisplayZoneWallClock(): void {
		$parsed = Timestamps::parse('2026-08-20T06:19:41', $this->berlin);
		$this->assertNotNull($parsed);
		$this->assertSame('2026-08-20 06:19:41 +02:00', $parsed->format('Y-m-d H:i:s P'));
		$this->assertSame(
			(new DateTimeImmutable('2026-08-20T06:19:41', $this->berlin))->getTimestamp(),
			$parsed->getTimestamp(),
		);
	}

	/** The same instant buckets to different days in different zones. */
	public function testDayKeyFollowsTheDisplayZone(): void {
		$lateEvening = Timestamps::parse('2026-08-20T23:30:00+02:00', $this->berlin);
		$this->assertNotNull($lateEvening);
		$this->assertSame('2026-08-20', Timestamps::dayKey($lateEvening, $this->berlin));
		$this->assertSame('2026-08-20',
			Timestamps::dayKey($lateEvening, new DateTimeZone('UTC')));

		$justPastMidnight = Timestamps::parse('2026-08-21T00:30:00+02:00', $this->berlin);
		$this->assertNotNull($justPastMidnight);
		$this->assertSame('2026-08-21', Timestamps::dayKey($justPastMidnight, $this->berlin));
		// 00:30 Berlin is still 22:30 the previous day in UTC.
		$this->assertSame('2026-08-20',
			Timestamps::dayKey($justPastMidnight, new DateTimeZone('UTC')));
	}

	/**
	 * Elapsed time is absolute. On the night the clocks go back, 23:00 to 07:00
	 * is nine hours of sleep, not the eight the wall clock suggests.
	 *
	 * `DateTime::diff` gets this right too — checked here so the claim is on the
	 * record rather than assumed. Integer milliseconds are used for
	 * representation reasons, not because `diff` is wrong.
	 */
	public function testElapsedMillisIsAbsoluteAcrossADstChange(): void {
		// Europe/Berlin falls back on 2026-10-25: 03:00 becomes 02:00.
		$onset = Timestamps::parse('2026-10-24T23:00:00+02:00', $this->berlin);
		$wake = Timestamps::parse('2026-10-25T07:00:00+01:00', $this->berlin);
		$this->assertNotNull($onset);
		$this->assertNotNull($wake);

		$this->assertSame(9 * 3600 * 1000, Timestamps::elapsedMillis($onset, $wake));
		$this->assertSame(9, (int)$onset->diff($wake)->format('%h'));
		// The wall clock, which is what a naive reading of the two strings gives.
		$this->assertSame('23:00', $onset->format('H:i'));
		$this->assertSame('07:00', $wake->format('H:i'));
	}

	public function testMinutesToMillisRoundsHalfAwayFromZero(): void {
		$this->assertSame(60000, Timestamps::minutesToMillis(1.0));
		$this->assertSame(330 * 60000, Timestamps::minutesToMillis(330.0));
		$this->assertSame(671000, Timestamps::minutesToMillis(11.183333333333334));
		$this->assertSame(0, Timestamps::minutesToMillis(0.0000083));
		$this->assertSame(1, Timestamps::minutesToMillis(0.00001));
	}

	public function testEpochSecondsIdentifiesTheSameInstantAcrossOffsets(): void {
		$berlin = Timestamps::parse('2026-08-20T06:19:41+02:00', $this->berlin);
		$utc = Timestamps::parse('2026-08-20T04:19:41Z', $this->berlin);
		$this->assertNotNull($berlin);
		$this->assertNotNull($utc);
		$this->assertSame(Timestamps::epochSeconds($berlin), Timestamps::epochSeconds($utc));
	}

	public function testStartOfDayIsLocalMidnight(): void {
		$midnight = Timestamps::startOfDay('2026-08-20', $this->berlin);
		$this->assertSame('2026-08-20 00:00:00 +02:00', $midnight->format('Y-m-d H:i:s P'));
	}
}
