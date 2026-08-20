<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit;

use OCA\Cairn\Reading\HealthQueryService;
use OCA\Cairn\Reading\Model\DailyStat;
use OCA\Cairn\Reading\Model\DailyValue;
use OCA\Cairn\Reading\Model\HealthMetric;
use OCA\Cairn\Reading\Model\ScalarReading;
use OCA\Cairn\Tests\Support\FixedClock;
use OCA\Cairn\Tests\Support\InMemoryShardSource;
use OCA\Cairn\Tests\Support\Points;
use OCA\Cairn\Tests\Support\Readings;
use PHPUnit\Framework\TestCase;

final class HealthQueryServiceTest extends TestCase {
	private const TODAY = '2026-08-20';

	private InMemoryShardSource $shards;

	protected function setUp(): void {
		$this->shards = new InMemoryShardSource();
	}

	private function service(int $lookbackDays = HealthQueryService::DEFAULT_LOOKBACK_DAYS): HealthQueryService {
		return new HealthQueryService(
			shards: $this->shards,
			clock: FixedClock::at(self::TODAY . ' 12:00'),
			display: Readings::zone(),
			lookbackDays: $lookbackDays,
		);
	}

	// ---------------------------------------------------------------- steps

	/**
	 * The Samsung case, end to end from raw lines: one whole-day record re-read
	 * through the day. The total is the newest snapshot plus the distinct
	 * per-interval deltas — not the sum of the snapshots.
	 */
	public function testTodayStepTotalResolvesCumulativeSnapshots(): void {
		$this->shards->add(HealthMetric::Steps, self::TODAY,
			Points::steps(3100.0, '00:00:00', '23:59:59', '09:05'),
			Points::steps(9040.0, '00:00:00', '23:59:59', '15:05'),
			Points::steps(14210.0, '00:00:00', '23:59:59', '22:05'),
			Points::steps(4.0, '06:08:12', '06:08:18', '06:42', Points::PLATFORM),
			Points::steps(10.0, '06:28:57', '06:29:03', '06:42', Points::PLATFORM),
		);

		self::assertSame(14224.0, $this->service()->todayStepTotal());
	}

	/**
	 * `null`, not `0`. "No sync yet" and "you did not move" are different
	 * answers and only one of them is a measurement.
	 */
	public function testTodayStepTotalIsNullWhenNothingHasArrived(): void {
		self::assertNull($this->service()->todayStepTotal());
	}

	/** The chart, by contrast, must keep a slot for every day. */
	public function testDailyStepsZeroFillsMissingDaysOldestFirst(): void {
		$this->shards->add(HealthMetric::Steps, self::TODAY,
			Points::steps(500.0, '00:00:00', '23:59:59', '22:05'));
		$this->shards->add(HealthMetric::Steps, '2026-08-18',
			Points::steps(900.0, '2026-08-18 00:00:00', '2026-08-18 23:59:59', '2026-08-18 22:05'));

		$series = $this->service()->dailySteps(4);

		self::assertSame(
			['2026-08-17', '2026-08-18', '2026-08-19', '2026-08-20'],
			array_map(static fn (DailyValue $d): string => $d->day, $series),
		);
		self::assertSame([0.0, 900.0, 0.0, 500.0],
			array_map(static fn (DailyValue $d): float => $d->value, $series));
	}

	/** Snapshots from different days must never be compared with each other. */
	public function testDailyStepsResolvesEachDaySeparately(): void {
		foreach (['2026-08-19', self::TODAY] as $day) {
			$this->shards->add(HealthMetric::Steps, $day,
				Points::steps(1000.0, "{$day} 00:00:00", "{$day} 23:59:59", "{$day} 09:00"),
				Points::steps(8000.0, "{$day} 00:00:00", "{$day} 23:59:59", "{$day} 22:00"));
		}

		$series = $this->service()->dailySteps(2);
		self::assertSame([8000.0, 8000.0],
			array_map(static fn (DailyValue $d): float => $d->value, $series));
	}

	// ----------------------------------------------------------- heart rate

	public function testDailyHeartRateReportsSpreadAndOmitsEmptyDays(): void {
		$this->shards->add(HealthMetric::HeartRate, self::TODAY,
			Points::heartRate(50.0, '01:00', '23:00'),
			Points::heartRate(70.0, '12:00', '23:00'),
			Points::heartRate(90.0, '18:00', '23:00'));

		$stats = $this->service()->dailyHeartRate(3);

		self::assertCount(1, $stats, 'the two empty days are omitted, not zeroed');
		self::assertSame(self::TODAY, $stats[0]->day);
		self::assertSame(50.0, $stats[0]->min);
		self::assertSame(90.0, $stats[0]->max);
		self::assertSame(70.0, $stats[0]->mean);
		self::assertSame(3, $stats[0]->count);
	}

	/**
	 * Readings are filed by their own timestamp, not by the shard they sat in.
	 * A late-evening reading written into the next day's shard still belongs to
	 * the evening it was taken.
	 */
	public function testHeartRateIsBucketedByItsOwnTimestamp(): void {
		$this->shards->add(HealthMetric::HeartRate, self::TODAY,
			Points::heartRate(55.0, '2026-08-19 23:30', '2026-08-20 06:00'),
			Points::heartRate(65.0, '2026-08-20 08:00', '2026-08-20 09:00'));

		$stats = $this->service()->dailyHeartRate(2);

		self::assertSame(['2026-08-19', '2026-08-20'],
			array_map(static fn (DailyStat $s): string => $s->day, $stats));
	}

	// --------------------------------------------------------------- weight

	public function testLatestScalarWalksBackToTheMostRecentDayWithData(): void {
		$this->shards->add(HealthMetric::Weight, '2026-08-17',
			Points::weight(88.0, '2026-08-17 06:20', '2026-08-17 07:00'));

		$latest = $this->service()->latestScalar(HealthMetric::Weight);

		self::assertNotNull($latest);
		self::assertSame(88.0, $latest->value);
		self::assertSame('kg', $latest->unit);
	}

	public function testLatestScalarAppliesTheCorrectionWithinItsDay(): void {
		$this->shards->add(HealthMetric::Weight, self::TODAY,
			Points::weight(98.4, '06:21', '06:25'),
			Points::weight(88.4, '06:21', '09:02'));

		$latest = $this->service()->latestScalar(HealthMetric::Weight);
		self::assertNotNull($latest);
		self::assertSame(88.4, $latest->value, 'the corrected value supersedes the mistyped one');
	}

	public function testLatestScalarStopsAtTheLookbackHorizon(): void {
		$this->shards->add(HealthMetric::Weight, '2026-08-15',
			Points::weight(88.0, '2026-08-15 06:20', '2026-08-15 07:00'));

		self::assertNotNull($this->service(lookbackDays: 5)->latestScalar(HealthMetric::Weight));
		self::assertNull($this->service(lookbackDays: 3)->latestScalar(HealthMetric::Weight));
	}

	/** The lookback is a span, so ninety days back includes ninety-one dates. */
	public function testTheLookbackSpanIsInclusiveOfBothEnds(): void {
		$this->service(lookbackDays: 90)->latestScalar(HealthMetric::Weight);

		$days = $this->shards->daysReadFor(HealthMetric::Weight);
		self::assertCount(91, $days);
		self::assertSame('2026-05-22', $days[0]);
		self::assertSame(self::TODAY, $days[90]);
	}

	public function testScalarSeriesIsOldestFirst(): void {
		$this->shards->add(HealthMetric::Weight, self::TODAY,
			Points::weight(88.5, '06:30', '07:00'));
		$this->shards->add(HealthMetric::Weight, '2026-08-19',
			Points::weight(88.9, '2026-08-19 06:30', '2026-08-19 07:00'));

		$series = $this->service()->scalarSeries(HealthMetric::Weight, 3);

		self::assertSame([88.9, 88.5],
			array_map(static fn (ScalarReading $r): float => $r->value, $series));
	}

	// ------------------------------------------------------------- activity

	/** No dedup: two sources recording one run are two records of it. */
	public function testRecentWorkoutsKeepsDuplicatesAndSortsNewestFirst(): void {
		$this->shards->add(HealthMetric::Activity, self::TODAY,
			Points::workout('RUNNING', '18:00', '18:42', Points::VENDOR),
			Points::workout('RUNNING', '18:00', '18:42', Points::WEARABLE),
			Points::workout('WALKING', '09:00', '09:30'));

		$workouts = $this->service()->recentWorkouts(2);

		self::assertCount(3, $workouts);
		self::assertSame('RUNNING', $workouts[0]->activityName);
		self::assertSame('RUNNING', $workouts[1]->activityName);
		self::assertSame('WALKING', $workouts[2]->activityName);
		// The body claims 999 minutes; the window says 42.
		self::assertSame(42 * 60000, $workouts[0]->durationMillis());
	}

	// ---------------------------------------------------------------- sleep

	/**
	 * A night begins the evening before, so its onset segments live in the
	 * previous day's shard. Reading only today would report a sleep that started
	 * at midnight.
	 */
	public function testLastNightReadsBackFarEnoughToFindItsOnset(): void {
		$this->shards->add(HealthMetric::Sleep, '2026-08-19',
			Points::sleepStage('light', '2026-08-19 23:20', '2026-08-20 01:00'));
		$this->shards->add(HealthMetric::Sleep, self::TODAY,
			Points::sleepStage('deep', '2026-08-20 01:00', '2026-08-20 05:30'));

		$night = $this->service()->lastNight();

		self::assertNotNull($night);
		self::assertSame('2026-08-19 23:20', $night->start->format('Y-m-d H:i'));
		self::assertSame('2026-08-19', $night->night);
	}

	/** `n + 2` dates, where every other query reads `n`. */
	public function testLastNNightsReadsTwoExtraDates(): void {
		$this->service()->lastNNights(3);

		$days = $this->shards->daysReadFor(HealthMetric::Sleep);
		self::assertCount(5, $days);
		self::assertSame('2026-08-16', $days[0]);
		self::assertSame(self::TODAY, $days[4]);
	}

	public function testNightsComeBackNewestFirstAndAreCapped(): void {
		foreach (['2026-08-17', '2026-08-18', '2026-08-19'] as $day) {
			$this->shards->add(HealthMetric::Sleep, $day,
				Points::sleepStage('deep', "{$day} 01:00", "{$day} 05:00"));
		}

		$nights = $this->service()->lastNNights(2);

		self::assertCount(2, $nights);
		self::assertSame('2026-08-19', $nights[0]->night);
		self::assertSame('2026-08-18', $nights[1]->night);
	}

	/** Stored rollups are carried, never rendered. */
	public function testAStoredEpisodeDoesNotReplaceTheRecomputation(): void {
		$this->shards->add(HealthMetric::Sleep, self::TODAY,
			Points::sleepStage('deep', '01:00', '05:00'),
			Points::sleepEpisode('01:00', '05:00', 999.0));

		$night = $this->service()->lastNight();

		self::assertNotNull($night);
		self::assertSame(4 * 3600000, $night->totalSleepMillis);
		self::assertSame(0, $night->awakenings, 'not the stored 99');
		self::assertNotNull($night->storedEpisode);
	}

	public function testAnEpisodeWithNoStagesProducesNoNight(): void {
		$this->shards->add(HealthMetric::Sleep, self::TODAY,
			Points::sleepEpisode('00:30', '06:30', 330.0));

		self::assertNull($this->service()->lastNight());
	}

	/** Only the schema name discriminates inside the sleep shard. */
	public function testAnUnknownSleepSchemaIsIgnored(): void {
		$nonsense = str_replace('"name":"sleep-stage"', '"name":"sleep-nonsense"',
			Points::sleepStage('deep', '04:30', '05:30'));
		$this->shards->add(HealthMetric::Sleep, self::TODAY,
			Points::sleepStage('deep', '01:30', '04:30'),
			$nonsense);

		$night = $this->service()->lastNight();
		self::assertNotNull($night);
		self::assertSame(3 * 3600000, $night->totalSleepMillis, 'the nonsense line contributed nothing');
	}

	// ------------------------------------------------------------ resilience

	/**
	 * A damaged shard must degrade to "fewer readings", never to an error. The
	 * torn line is last, which is the only place a real one can be.
	 */
	public function testADamagedShardStillYieldsItsGoodReadings(): void {
		$this->shards->addRaw(HealthMetric::HeartRate, self::TODAY, implode("\n", [
			Points::heartRate(60.0, '10:00', '11:00'),
			'["not","an","object"]',
			'',
			'   ',
			Points::heartRate(80.0, '10:05', '11:00'),
			'{"header":{"id":"9f0c1f2e-0000-4000-8000-0000000',
		]));

		$stats = $this->service()->dailyHeartRate(1);

		self::assertCount(1, $stats);
		self::assertSame(2, $stats[0]->count);
		self::assertSame(70.0, $stats[0]->mean);
	}

	public function testEveryQuerySurvivesAnEmptyFolder(): void {
		$service = $this->service();

		self::assertNull($service->latestScalar(HealthMetric::Weight));
		self::assertNull($service->todayStepTotal());
		self::assertNull($service->lastNight());
		self::assertSame([], $service->dailyHeartRate(7));
		self::assertSame([], $service->scalarSeries(HealthMetric::Weight, 7));
		self::assertSame([], $service->recentWorkouts(7));
		self::assertSame([], $service->lastNNights(3));
		self::assertCount(7, $service->dailySteps(7));
	}
}
