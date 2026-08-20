<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Sleep;

use OCA\Cairn\Reading\Model\SleepEpisodeReading;
use OCA\Cairn\Reading\Model\SleepStage;
use OCA\Cairn\Reading\Sleep\NightReconciler;
use OCA\Cairn\Tests\Support\Readings;
use PHPUnit\Framework\TestCase;

final class NightReconcilerTest extends TestCase {
	private const HOUR = 3600000;
	private const MINUTE = 60000;

	private NightReconciler $reconciler;

	protected function setUp(): void {
		$this->reconciler = new NightReconciler(Readings::zone());
	}

	private function stored(string $start, string $end, float $totalMinutes): SleepEpisodeReading {
		return new SleepEpisodeReading(
			start: Readings::at($start),
			end: Readings::at($end),
			totalSleepMillis: (int)round($totalMinutes * (float)self::MINUTE),
			isMainSleep: true,
			awakenings: 99,
		);
	}

	public function testNoStagesMeansNoNights(): void {
		self::assertSame([], $this->reconciler->reconcile([]));
	}

	/**
	 * Segments are the source of truth. A stored rollup on its own does not
	 * reconstruct a night, because the phone would not show one either.
	 */
	public function testAStoredEpisodeAloneDoesNotProduceANight(): void {
		$nights = $this->reconciler->reconcile([], [$this->stored('00:30', '06:30', 330.0)]);

		self::assertSame([], $nights);
	}

	public function testANightIsDescribedFromItsSegments(): void {
		$nights = $this->reconciler->reconcile([
			Readings::stage(SleepStage::Light, '2026-08-19 23:30', '2026-08-20 01:00', 'shealth'),
			Readings::stage(SleepStage::Awake, '2026-08-20 01:00', '2026-08-20 01:10', 'shealth'),
			Readings::stage(SleepStage::Deep, '2026-08-20 01:10', '2026-08-20 04:00', 'shealth'),
		]);

		self::assertCount(1, $nights);
		$night = $nights[0];
		self::assertSame('2026-08-19', $night->night, 'bucketed by onset, not by waking');
		self::assertSame(1, $night->awakenings);
		self::assertSame(['shealth'], $night->sources);
		self::assertCount(3, $night->stages);
		self::assertTrue($night->isMainSleep);
		self::assertTrue($night->hasStageBreakdown());
	}

	/** With wake markers present, the window is genuinely "in bed". */
	public function testEfficiencyIsReportedWhenWakeMarkersExist(): void {
		$nights = $this->reconciler->reconcile([
			Readings::stage(SleepStage::Light, '01:00', '02:00', 'shealth'),
			Readings::stage(SleepStage::Awake, '02:00', '03:00', 'shealth'),
			Readings::stage(SleepStage::Deep, '03:00', '04:00', 'shealth'),
		]);

		$night = $nights[0];
		self::assertSame(3 * self::HOUR, $night->timeInBedMillis);
		self::assertSame(2 * self::HOUR, $night->totalSleepMillis);
		self::assertNotNull($night->efficiency);
		self::assertEqualsWithDelta(2 / 3, $night->efficiency, 1e-9);
	}

	/**
	 * Without them the window is bounded by sleep itself, so efficiency would be
	 * a meaningless 100%. Reporting null is the honest answer.
	 */
	public function testEfficiencyIsNullWithoutWakeMarkers(): void {
		$nights = $this->reconciler->reconcile([
			Readings::stage(SleepStage::Session, '2026-08-19 23:00', '2026-08-20 06:00', 'shealth'),
		]);

		self::assertNull($nights[0]->efficiency);
		self::assertNull($nights[0]->timeInBedMillis);
		self::assertFalse($nights[0]->hasStageBreakdown());
	}

	public function testEveryContributingSourceIsListed(): void {
		$nights = $this->reconciler->reconcile([
			Readings::stage(SleepStage::Light, '01:00', '02:00', 'Galaxy Fit3'),
			Readings::stage(SleepStage::Deep, '02:00', '03:00', 'shealth'),
			Readings::stage(SleepStage::Rem, '03:00', '04:00'),
		]);

		$sources = $nights[0]->sources;
		sort($sources);
		self::assertSame(['Galaxy Fit3', 'shealth', 'unknown'], $sources);
	}

	/** The stored rollup is attached for comparison and never displayed. */
	public function testTheStoredEpisodeIsAttachedButNeverReplacesTheRecomputation(): void {
		$nights = $this->reconciler->reconcile(
			[
				Readings::stage(SleepStage::Light, '01:00', '03:00', 'shealth'),
				Readings::stage(SleepStage::Deep, '03:00', '05:00', 'shealth'),
			],
			[$this->stored('01:00', '05:00', 999.0)],
		);

		$night = $nights[0];
		self::assertNotNull($night->storedEpisode);
		self::assertSame(999 * self::MINUTE, $night->storedEpisode->totalSleepMillis);
		self::assertSame(99, $night->storedEpisode->awakenings);
		// What is actually presented comes from the segments.
		self::assertSame(4 * self::HOUR, $night->totalSleepMillis);
		self::assertSame(0, $night->awakenings);
	}

	/** Touching is not overlapping: that is a different sleep. */
	public function testAStoredEpisodeThatMerelyTouchesIsNotMatched(): void {
		$nights = $this->reconciler->reconcile(
			[Readings::stage(SleepStage::Deep, '01:00', '05:00', 'shealth')],
			[$this->stored('05:00', '07:00', 120.0)],
		);

		self::assertNull($nights[0]->storedEpisode);
	}

	public function testAnOverlappingStoredEpisodeIsMatched(): void {
		$nights = $this->reconciler->reconcile(
			[Readings::stage(SleepStage::Deep, '01:00', '05:00', 'shealth')],
			[$this->stored('04:59', '07:00', 120.0)],
		);

		self::assertNotNull($nights[0]->storedEpisode);
	}

	/**
	 * Deduplication runs before grouping, so a contested window cannot inflate
	 * the awakening count of the night it belongs to.
	 */
	public function testSegmentsAreDeduplicatedBeforeTheNightIsMeasured(): void {
		$nights = $this->reconciler->reconcile([
			Readings::stage(SleepStage::Light, '00:30', '02:00', 'Galaxy Fit3'),
			Readings::stage(SleepStage::Deep, '02:00', '02:40', 'Galaxy Fit3'),
			Readings::stage(SleepStage::Awake, '02:00', '02:40', 'com.sec.android.app.shealth'),
			Readings::stage(SleepStage::Rem, '02:40', '05:00', 'Galaxy Fit3'),
		]);

		self::assertCount(1, $nights);
		self::assertSame(0, $nights[0]->awakenings, 'the wearable called it deep sleep');
		self::assertSame(4 * self::HOUR + 30 * self::MINUTE, $nights[0]->totalSleepMillis);
		self::assertCount(3, $nights[0]->stages);
	}

	public function testANapAfterALongGapBecomesItsOwnNight(): void {
		$nights = $this->reconciler->reconcile([
			Readings::stage(SleepStage::Light, '2026-08-19 23:20', '2026-08-20 01:00', 'shealth'),
			Readings::stage(SleepStage::Deep, '2026-08-20 01:45', '2026-08-20 05:30', 'shealth'),
			Readings::stage(SleepStage::Light, '2026-08-20 07:00', '2026-08-20 08:00', 'shealth'),
		]);

		self::assertCount(2, $nights);
		// The 45-minute break kept the long sleep together; the 90-minute one
		// split the nap off.
		self::assertSame('2026-08-19', $nights[0]->night);
		self::assertSame('2026-08-20', $nights[1]->night);
		// 23:20-01:00 is 100 minutes, 01:45-05:30 is 225; the 45-minute gap
		// between them is not sleep.
		self::assertSame(5 * self::HOUR + 25 * self::MINUTE, $nights[0]->totalSleepMillis);
		self::assertSame(self::HOUR, $nights[1]->totalSleepMillis);
	}

	/**
	 * A surprise worth pinning down: a morning nap can be flagged as main sleep
	 * even though a much longer sleep just ended.
	 *
	 * Main sleep is decided per calendar night, keyed on the *onset* date. A
	 * sleep that began at 23:20 belongs to the previous day, so the nap is the
	 * only episode its own day owns and therefore that day's longest. The phone
	 * does the same thing with the same files, which is the property that has to
	 * hold — but it is easy to "fix" by accident while porting, and doing so
	 * would make the two frontends disagree.
	 */
	public function testANapIsMainForItsOwnDateWhenTheNightBeganBeforeMidnight(): void {
		$nights = $this->reconciler->reconcile([
			Readings::stage(SleepStage::Deep, '2026-08-19 23:20', '2026-08-20 05:30', 'shealth'),
			Readings::stage(SleepStage::Light, '2026-08-20 07:00', '2026-08-20 08:00', 'shealth'),
		]);

		self::assertCount(2, $nights);
		self::assertTrue($nights[0]->isMainSleep, 'longest sleep of the 19th');
		self::assertTrue($nights[1]->isMainSleep, 'and the only sleep of the 20th');
	}

	/** Within one calendar date, though, the shorter episode is not main. */
	public function testANapOnTheSameDateAsTheMainSleepIsNotMain(): void {
		$nights = $this->reconciler->reconcile([
			Readings::stage(SleepStage::Deep, '2026-08-20 01:00', '2026-08-20 05:30', 'shealth'),
			Readings::stage(SleepStage::Light, '2026-08-20 14:00', '2026-08-20 14:40', 'shealth'),
		]);

		self::assertCount(2, $nights);
		self::assertSame('2026-08-20', $nights[0]->night);
		self::assertSame('2026-08-20', $nights[1]->night);
		self::assertTrue($nights[0]->isMainSleep);
		self::assertFalse($nights[1]->isMainSleep, 'same date, and shorter');
	}
}
