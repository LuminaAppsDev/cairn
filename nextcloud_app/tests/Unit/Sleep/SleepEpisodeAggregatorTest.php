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
		// And the breakdown adds up to exactly that, rather than to 780 — the
		// session claims only the minutes no finer stage accounted for.
		self::assertSame(
			$episodes[0]->totalSleepMillis,
			array_sum($episodes[0]->perStageMillis),
		);
	}

	/**
	 * The breakdown is a partition, not a tally.
	 *
	 * A plain sum per stage double-counts, because the whole-night `session`
	 * covers the very minutes the light/deep/rem segments describe. Each stage
	 * claims only what no more specific stage has already claimed, which leaves
	 * `session` meaning what it honestly is: asleep, stage unrecorded.
	 */
	public function testPerStageIsAPartitionOfTheNight(): void {
		$episodes = $this->aggregator->aggregate([
			Readings::stage(SleepStage::Session, '01:00', '05:00'),
			Readings::stage(SleepStage::Light, '01:00', '02:00'),
			Readings::stage(SleepStage::Awake, '02:00', '02:30'),
			Readings::stage(SleepStage::Deep, '02:30', '03:30'),
			Readings::stage(SleepStage::Rem, '03:30', '04:00'),
		]);

		$stages = $episodes[0]->perStageMillis;
		self::assertSame(60 * self::MINUTE, $stages['light']);
		self::assertSame(30 * self::MINUTE, $stages['awake']);
		self::assertSame(60 * self::MINUTE, $stages['deep']);
		self::assertSame(30 * self::MINUTE, $stages['rem']);
		// 04:00-05:00 is the only stretch no finer stage described.
		self::assertSame(60 * self::MINUTE, $stages['session']);
		// Everything together is the whole four-hour window.
		self::assertSame(4 * self::HOUR, array_sum($stages));
	}

	/**
	 * The invariant that ties the breakdown to the headline figure: whatever a
	 * chart shows as sleep must add up to the number beside it.
	 */
	public function testSleepStagesSumToTotalSleep(): void {
		$episodes = $this->aggregator->aggregate([
			Readings::stage(SleepStage::Session, '01:00', '05:00'),
			Readings::stage(SleepStage::Light, '01:00', '02:00'),
			Readings::stage(SleepStage::Awake, '02:00', '02:30'),
			Readings::stage(SleepStage::Light, '02:30', '03:30'),
			Readings::stage(SleepStage::Awake, '03:30', '04:00'),
			Readings::stage(SleepStage::Rem, '04:00', '05:00'),
		]);

		$episode = $episodes[0];
		$asleep = 0;
		foreach ($episode->perStageMillis as $wire => $millis) {
			if (SleepStage::from($wire)->isAsleep()) {
				$asleep += $millis;
			}
		}

		self::assertSame($episode->totalSleepMillis, $asleep);
		self::assertSame(3 * self::HOUR, $asleep);
	}

	/** Repeated segments of one stage are one stretch, not two. */
	public function testOverlappingSameStageSegmentsAreNotDoubleCounted(): void {
		$episodes = $this->aggregator->aggregate([
			Readings::stage(SleepStage::Deep, '01:00', '03:00'),
			Readings::stage(SleepStage::Deep, '02:00', '04:00'),
		]);

		self::assertSame(3 * self::HOUR, $episodes[0]->perStageMillis['deep']);
		self::assertSame(3 * self::HOUR, $episodes[0]->totalSleepMillis);
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
