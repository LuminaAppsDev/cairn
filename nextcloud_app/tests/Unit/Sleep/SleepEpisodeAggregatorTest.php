<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Sleep;

use OCA\Cairn\Reading\Model\SleepStage;
use OCA\Cairn\Reading\Sleep\SleepEpisodeAggregator;
use OCA\Cairn\Tests\Support\Readings;
use PHPUnit\Framework\TestCase;

final class SleepEpisodeAggregatorTest extends TestCase {
	private SleepEpisodeAggregator $aggregator;

	protected function setUp(): void {
		$this->aggregator = new SleepEpisodeAggregator(Readings::zone());
	}

	private const HOUR = 3600000;
	private const MINUTE = 60000;

	public function testNoSegmentsMeansNoEpisodes(): void {
		self::assertSame([], $this->aggregator->aggregate([]));
	}

	/** A short break is a trip to the bathroom, not the end of the night. */
	public function testAGapUnderTheToleranceKeepsOneEpisode(): void {
		$episodes = $this->aggregator->aggregate([
			Readings::stage(SleepStage::Light, '2026-08-19 23:20', '2026-08-20 01:00'),
			Readings::stage(SleepStage::Deep, '2026-08-20 01:45', '2026-08-20 03:30'),
		]);

		self::assertCount(1, $episodes);
		self::assertSame('2026-08-19 23:20', $episodes[0]->start->format('Y-m-d H:i'));
		self::assertSame('2026-08-20 03:30', $episodes[0]->end->format('Y-m-d H:i'));
	}

	public function testAGapOverTheToleranceStartsANewEpisode(): void {
		$episodes = $this->aggregator->aggregate([
			Readings::stage(SleepStage::Deep, '01:00', '05:30'),
			Readings::stage(SleepStage::Light, '07:00', '08:00'),
		]);

		self::assertCount(2, $episodes);
	}

	/** Strictly greater: a gap of exactly the tolerance stays together. */
	public function testAGapOfExactlyTheToleranceDoesNotSplit(): void {
		$exactly = $this->aggregator->aggregate([
			Readings::stage(SleepStage::Deep, '01:00', '02:00'),
			Readings::stage(SleepStage::Deep, '03:00', '04:00'),
		]);
		self::assertCount(1, $exactly, '60 minutes is within tolerance');

		$oneSecondMore = $this->aggregator->aggregate([
			Readings::stage(SleepStage::Deep, '01:00:00', '02:00:00'),
			Readings::stage(SleepStage::Deep, '03:00:01', '04:00:00'),
		]);
		self::assertCount(2, $oneSecondMore, '60 minutes and a second is not');
	}

	/**
	 * Grouping compares against the running maximum end, not the previous
	 * segment's. A whole-night `session` followed by its own short sub-stages
	 * must not be split apart by them.
	 */
	public function testAnOverlappingLongSegmentDoesNotSplitTheNight(): void {
		$episodes = $this->aggregator->aggregate([
			Readings::stage(SleepStage::Session, '2026-08-19 23:30', '2026-08-20 06:00'),
			Readings::stage(SleepStage::Light, '2026-08-19 23:40', '2026-08-20 01:00'),
			Readings::stage(SleepStage::Deep, '2026-08-20 01:00', '2026-08-20 03:00'),
			Readings::stage(SleepStage::Rem, '2026-08-20 03:00', '2026-08-20 05:30'),
		]);

		self::assertCount(1, $episodes);
	}

	/**
	 * Total sleep is the union of the asleep intervals. Summing the session and
	 * its own sub-stages would report over eleven hours for a six-and-a-half
	 * hour night.
	 */
	public function testTotalSleepIsAUnionNotASum(): void {
		$episodes = $this->aggregator->aggregate([
			Readings::stage(SleepStage::Session, '2026-08-19 23:30', '2026-08-20 06:00'),
			Readings::stage(SleepStage::Light, '2026-08-19 23:40', '2026-08-20 01:00'),
			Readings::stage(SleepStage::Deep, '2026-08-20 01:00', '2026-08-20 03:00'),
			Readings::stage(SleepStage::Rem, '2026-08-20 03:00', '2026-08-20 05:30'),
		]);

		self::assertCount(1, $episodes);
		// 23:30 to 06:00 is 390 minutes; the naive sum would be 780.
		self::assertSame(390 * self::MINUTE, $episodes[0]->totalSleepMillis);
		self::assertGreaterThan(
			$episodes[0]->totalSleepMillis,
			array_sum($episodes[0]->perStageMillis),
			'the per-stage sum double-counts by design; total sleep must not',
		);
	}

	public function testTouchingAsleepIntervalsMergeIntoOneStretch(): void {
		$episodes = $this->aggregator->aggregate([
			Readings::stage(SleepStage::Light, '01:00', '02:00'),
			Readings::stage(SleepStage::Deep, '02:00', '03:00'),
		]);

		self::assertSame(2 * self::HOUR, $episodes[0]->totalSleepMillis);
	}

	/** Awake time is inside the episode but is not sleep. */
	public function testAwakeSegmentsAreExcludedFromTotalSleepAndCounted(): void {
		$episodes = $this->aggregator->aggregate([
			Readings::stage(SleepStage::Light, '01:00', '02:00'),
			Readings::stage(SleepStage::Awake, '02:00', '02:15'),
			Readings::stage(SleepStage::Deep, '02:15', '03:15'),
			Readings::stage(SleepStage::Awake, '03:15', '03:20'),
			Readings::stage(SleepStage::Rem, '03:20', '04:00'),
		]);

		self::assertCount(1, $episodes);
		self::assertSame(2 * self::HOUR + 40 * self::MINUTE, $episodes[0]->totalSleepMillis);
		self::assertSame(2, $episodes[0]->awakenings);
	}

	/** `in_bed` is a position, not a waking. */
	public function testInBedAndOutOfBedAreNotAwakenings(): void {
		$episodes = $this->aggregator->aggregate([
			Readings::stage(SleepStage::InBed, '00:50', '01:00'),
			Readings::stage(SleepStage::Light, '01:00', '02:00'),
			Readings::stage(SleepStage::OutOfBed, '02:00', '02:10'),
		]);

		self::assertSame(0, $episodes[0]->awakenings);
		self::assertSame(self::HOUR, $episodes[0]->totalSleepMillis);
	}

	/** The night's longest sleep is the main one; a nap is not. */
	public function testTheLongerEpisodeIsTheMainSleep(): void {
		$episodes = $this->aggregator->aggregate([
			Readings::stage(SleepStage::Deep, '01:00', '05:30'),
			Readings::stage(SleepStage::Light, '07:00', '08:00'),
		]);

		self::assertCount(2, $episodes);
		self::assertTrue($episodes[0]->isMainSleep);
		self::assertFalse($episodes[1]->isMainSleep);
	}

	/** Nothing in the data breaks an exact tie, so both are flagged. */
	public function testAnExactTieFlagsBothAsMain(): void {
		$episodes = $this->aggregator->aggregate([
			Readings::stage(SleepStage::Deep, '02:00', '04:00'),
			Readings::stage(SleepStage::Deep, '09:00', '11:00'),
		]);

		self::assertCount(2, $episodes);
		self::assertTrue($episodes[0]->isMainSleep);
		self::assertTrue($episodes[1]->isMainSleep);
	}

	/** An episode of pure wakefulness is nobody's main sleep. */
	public function testAnEpisodeWithNoSleepIsNeverMain(): void {
		$episodes = $this->aggregator->aggregate([
			Readings::stage(SleepStage::Awake, '02:00', '02:30'),
		]);

		self::assertSame(0, $episodes[0]->totalSleepMillis);
		self::assertFalse($episodes[0]->isMainSleep);
	}

	/** Main sleep is decided per calendar night, by the episode's onset. */
	public function testMainSleepIsScopedToTheNightOfOnset(): void {
		$episodes = $this->aggregator->aggregate([
			Readings::stage(SleepStage::Deep, '2026-08-19 01:00', '2026-08-19 03:00'),
			Readings::stage(SleepStage::Deep, '2026-08-20 01:00', '2026-08-20 02:00'),
		]);

		self::assertCount(2, $episodes);
		self::assertTrue($episodes[0]->isMainSleep, 'longest on the 19th');
		self::assertTrue($episodes[1]->isMainSleep, 'and the only one on the 20th');
	}

	public function testASessionOnlyNightHasNoStageBreakdown(): void {
		$episodes = $this->aggregator->aggregate([
			Readings::stage(SleepStage::Session, '2026-08-19 23:00', '2026-08-20 06:00'),
		]);

		self::assertFalse($episodes[0]->hasStageBreakdown());

		$withStages = $this->aggregator->aggregate([
			Readings::stage(SleepStage::Session, '2026-08-19 23:00', '2026-08-20 06:00'),
			Readings::stage(SleepStage::Deep, '2026-08-20 01:00', '2026-08-20 02:00'),
		]);
		self::assertTrue($withStages[0]->hasStageBreakdown());
	}

	/**
	 * Clocks go back on 2026-10-25, so 23:00 to 07:00 really is nine hours in
	 * bed. Wall-clock arithmetic would report eight.
	 */
	public function testANightSpanningTheDstFallBackIsMeasuredInRealTime(): void {
		$episodes = $this->aggregator->aggregate([
			Readings::stage(SleepStage::Session, '2026-10-24 23:00', '2026-10-25 07:00'),
		]);

		self::assertCount(1, $episodes);
		self::assertSame(9 * self::HOUR, $episodes[0]->totalSleepMillis);
	}
}
