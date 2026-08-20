<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Service;

use OCA\Cairn\Service\DashboardAssembler;
use OCA\Cairn\Tests\Support\BuildsApp;
use OCA\Cairn\Tests\Support\Points;
use PHPUnit\Framework\TestCase;

/**
 * Shaping read-path results into what the frontend consumes.
 *
 * The rules that could make two readers disagree live in `lib/Reading/` and are
 * pinned by the shared parity fixtures. What is decided here is narrower and
 * safe to differ — but not arbitrary: how an average is taken changes what a
 * number means.
 */
final class DashboardAssemblerTest extends TestCase {
	use BuildsApp;

	private DashboardAssembler $assembler;

	protected function setUp(): void {
		$this->assembler = new DashboardAssembler();
	}

	/** @param array<string, string> $tree */
	private function queries(array $tree): \OCA\Cairn\Reading\HealthQueryService {
		return $this->queryFactoryFor($tree)->forUser('admin');
	}

	private function stepsOn(string $day, float $value): array {
		return ["steps/2026/{$day}.jsonl" => Points::steps(
			$value,
			"{$day} 00:00:00",
			"{$day} 23:59:59",
			"{$day} 22:00",
		) . "\n"];
	}

	/**
	 * Averaged over days that reported, not over the window.
	 *
	 * A day with no sync is missing data. Folding it in as a zero would drag the
	 * average down and make a gap look like inactivity — a different claim about
	 * somebody's week than the data supports.
	 */
	public function testTheStepAverageIgnoresDaysWithNoData(): void {
		$tree = $this->stepsOn('2026-08-20', 10000.0) + $this->stepsOn('2026-08-19', 6000.0);

		$payload = $this->assembler->steps($this->queries($tree), 7);

		self::assertSame(8000.0, $payload['average'], 'the mean of the two days that reported');
		self::assertSame(2, $payload['daysReported']);
		self::assertCount(7, $payload['series'], 'the chart still keeps every slot');
	}

	public function testTheStepAverageIsNullWhenNothingReported(): void {
		$payload = $this->assembler->steps($this->queries([]), 7);

		self::assertNull($payload['average']);
		self::assertNull($payload['today']);
		self::assertSame(0, $payload['daysReported']);
	}

	/**
	 * Weighted by sample count. Averaging the daily means would give a day with
	 * three readings the same say as one with three hundred.
	 */
	public function testTheHeartRateMeanIsWeightedBySampleCount(): void {
		$tree = [
			// One reading at 180 on one day...
			'heart-rate/2026/2026-08-19.jsonl'
				=> Points::heartRate(180.0, '2026-08-19 12:00', '2026-08-19 23:00') . "\n",
			// ...and three at 60 on the next.
			'heart-rate/2026/2026-08-20.jsonl'
				=> Points::heartRate(60.0, '2026-08-20 10:00', '2026-08-20 23:00') . "\n"
				. Points::heartRate(60.0, '2026-08-20 11:00', '2026-08-20 23:00') . "\n"
				. Points::heartRate(60.0, '2026-08-20 12:00', '2026-08-20 23:00') . "\n",
		];

		$payload = $this->assembler->heartRate($this->queries($tree), 7);

		self::assertSame(4, $payload['samples']);
		// (180 + 60 + 60 + 60) / 4 = 90. Averaging the daily means gives 120.
		self::assertSame(90.0, $payload['mean']);
		self::assertSame(60.0, $payload['min']);
		self::assertSame(180.0, $payload['max']);
	}

	public function testHeartRateIsEmptyRatherThanZeroWhenNothingReported(): void {
		$payload = $this->assembler->heartRate($this->queries([]), 7);

		self::assertNull($payload['mean'], 'zero would be a heart rate, and a false one');
		self::assertNull($payload['min']);
		self::assertNull($payload['max']);
		self::assertSame(0, $payload['samples']);
		self::assertSame([], $payload['series']);
	}

	/**
	 * The change spans the readings that exist, not the window asked for —
	 * otherwise the number silently means something different depending on how
	 * much history there is.
	 */
	public function testTheWeightChangeSpansTheReadingsThatExist(): void {
		$tree = [
			'weight/2026/2026-08-18.jsonl'
				=> Points::weight(90.0, '2026-08-18 06:20', '2026-08-18 07:00') . "\n",
			'weight/2026/2026-08-20.jsonl'
				=> Points::weight(88.5, '2026-08-20 06:20', '2026-08-20 07:00') . "\n",
		];

		$payload = $this->assembler->weight($this->queries($tree), 90);

		self::assertSame(-1.5, $payload['change']);
		self::assertSame(88.5, $payload['latest']['value'], 'the newest, not the last read');
		self::assertCount(2, $payload['series']);
	}

	public function testASingleWeightReadingHasNoChange(): void {
		$tree = ['weight/2026/2026-08-20.jsonl'
			=> Points::weight(88.5, '2026-08-20 06:20', '2026-08-20 07:00') . "\n"];

		$payload = $this->assembler->weight($this->queries($tree), 90);

		self::assertSame(0.0, $payload['change'], 'one reading against itself');
		self::assertNotNull($payload['latest']);
	}

	public function testNoWeightAtAllIsNullNotZero(): void {
		$payload = $this->assembler->weight($this->queries([]), 90);

		self::assertNull($payload['change']);
		self::assertNull($payload['latest']);
		self::assertSame('kg', $payload['unit'], 'a sensible default so the UI has a label');
	}

	/** Workouts carry their segments' own numbers, and a recomputed duration. */
	public function testActivityReportsEachWorkoutAndTheTotal(): void {
		$tree = ['activity/2026/2026-08-20.jsonl'
			=> Points::workout('WALKING', '2026-08-20 17:00', '2026-08-20 17:30') . "\n"
			. Points::workout('RUNNING', '2026-08-20 18:00', '2026-08-20 18:20') . "\n"];

		$payload = $this->assembler->activity($this->queries($tree), 7);

		self::assertSame(2, $payload['count']);
		self::assertSame(50 * 60000, $payload['totalDurationMs']);
		self::assertSame('RUNNING', $payload['workouts'][0]['activity'], 'newest first');
		// The body claims 999 minutes; the window says 20.
		self::assertSame(20 * 60000, $payload['workouts'][0]['durationMs']);
	}

	/** The night carries its segments, so a hypnogram needs no second request. */
	public function testSleepCarriesTheSegmentsForACharT(): void {
		$tree = ['sleep/2026/2026-08-20.jsonl'
			=> Points::sleepStage('light', '2026-08-20 01:00', '2026-08-20 02:00') . "\n"
			. Points::sleepStage('deep', '2026-08-20 02:00', '2026-08-20 04:00') . "\n"];

		$payload = $this->assembler->sleep($this->queries($tree), 1);

		self::assertCount(1, $payload['nights']);
		$night = $payload['nights'][0];
		self::assertSame(3 * 3600000, $night['totalSleepMs']);
		self::assertCount(2, $night['segments']);
		self::assertSame(['deep' => 2 * 3600000, 'light' => 3600000], $night['perStageMs']);
	}
}
