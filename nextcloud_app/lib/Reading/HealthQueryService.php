<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading;

use DateTimeImmutable;
use DateTimeZone;
use OCA\Cairn\Reading\Json\Timestamps;
use OCA\Cairn\Reading\Model\DailyStat;
use OCA\Cairn\Reading\Model\DailyValue;
use OCA\Cairn\Reading\Model\HealthMetric;
use OCA\Cairn\Reading\Model\NightSleep;
use OCA\Cairn\Reading\Model\ScalarReading;
use OCA\Cairn\Reading\Model\SleepEpisodeReading;
use OCA\Cairn\Reading\Model\SleepStageReading;
use OCA\Cairn\Reading\Model\WorkoutReading;
use OCA\Cairn\Reading\Parser\OmhReadingParser;
use OCA\Cairn\Reading\Resolve\IntervalResolver;
use OCA\Cairn\Reading\Resolve\ScalarResolver;
use OCA\Cairn\Reading\Sleep\NightReconciler;

/**
 * The questions the dashboard asks of the files.
 *
 * Each method owns two things a caller should not have to know: how far back to
 * read, and which resolution rule applies to what it finds. The windows are not
 * uniform, and the differences are deliberate — see the note on
 * {@see self::lastNNights()} in particular.
 *
 * Everything is anchored to the display timezone. "Today", the day a reading
 * belongs to, and the date a night is filed under all use it, because the phone
 * uses the device zone for exactly those three things (DESIGN.md §4.3).
 */
final class HealthQueryService {
	/** How far back {@see self::latestScalar()} is willing to look. */
	public const DEFAULT_LOOKBACK_DAYS = 90;

	private readonly OmhReadingParser $parser;

	public function __construct(
		private readonly ShardSource $shards,
		private readonly Clock $clock,
		private readonly DateTimeZone $display,
		private readonly ScalarResolver $scalars = new ScalarResolver(),
		private readonly IntervalResolver $intervals = new IntervalResolver(),
		?OmhReadingParser $parser = null,
		private readonly int $lookbackDays = self::DEFAULT_LOOKBACK_DAYS,
	) {
		$this->parser = $parser ?? new OmhReadingParser($display);
	}

	/**
	 * The most recent reading of a scalar metric, or `null` if there is none in
	 * the lookback window.
	 *
	 * Walks backwards a day at a time and stops at the first day that yields
	 * anything, rather than reading ninety days to answer "what do I weigh".
	 * Deduplication therefore applies within that one day: a correction filed
	 * against an earlier day's reading is not seen, which is the accepted cost
	 * of not reading the whole window on every page load.
	 */
	public function latestScalar(HealthMetric $metric): ?ScalarReading {
		// `+ 1` because the lookback is a span, not a count: ninety days back
		// from today is ninety-one dates including today, and the mobile
		// reader's loop is inclusive at both ends.
		foreach ($this->daysBackFromToday($this->lookbackDays + 1) as $day) {
			$readings = $this->scalarsOn($metric, $day);
			if ($readings === []) {
				continue;
			}
			$resolved = $this->scalars->resolve($readings);
			usort($resolved, static fn (ScalarReading $a, ScalarReading $b): int => $b->at <=> $a->at);

			return $resolved[0];
		}

		return null;
	}

	/**
	 * Today's step total, or `null` if today has produced nothing yet.
	 *
	 * `null` rather than zero, deliberately: "no data has arrived" and "you have
	 * not moved" look identical as a number and mean very different things, and
	 * a dashboard that shows a confident 0 for a sync that has not run yet is
	 * lying about the day.
	 */
	public function todayStepTotal(): ?float {
		$readings = $this->intervalsOn(HealthMetric::Steps, $this->today());
		if ($readings === []) {
			return null;
		}

		$total = 0.0;
		foreach ($this->intervals->resolve($readings) as $reading) {
			$total += $reading->value;
		}

		return $total;
	}

	/**
	 * Step totals per day, oldest first, zero-filled.
	 *
	 * Zero-filled because this feeds a bar chart, where a missing day must
	 * occupy its slot rather than shifting every later bar left. That is the
	 * opposite choice from {@see self::todayStepTotal()}, and for the opposite
	 * reason: there the number is the answer, here it is a position on an axis.
	 *
	 * Resolved per day rather than across the window, so a cumulative whole-day
	 * snapshot is only ever compared against others of the same day.
	 *
	 * @return list<DailyValue>
	 */
	public function dailySteps(int $days = 14): array {
		$out = [];
		foreach ($this->daysBackFromToday($days) as $day) {
			$readings = $this->intervalsOn(HealthMetric::Steps, $day);
			$total = 0.0;
			foreach ($this->intervals->resolve($readings) as $reading) {
				$total += $reading->value;
			}
			$out[] = new DailyValue($day, $total);
		}

		return array_reverse($out);
	}

	/**
	 * Heart-rate spread per day, oldest first.
	 *
	 * Days with no readings are omitted rather than zero-filled: a zero would be
	 * a heart rate, and a false one.
	 *
	 * Readings are bucketed by the day of their own timestamp, not by the shard
	 * they were found in. Those differ whenever the writer's offset and the
	 * reader's zone disagree, and the reading's own time is the honest answer.
	 *
	 * @return list<DailyStat>
	 */
	public function dailyHeartRate(int $days = 14): array {
		$readings = [];
		foreach ($this->daysBackFromToday($days) as $day) {
			$readings = [...$readings, ...$this->scalarsOn(HealthMetric::HeartRate, $day)];
		}

		/** @var array<string, list<float>> $byDay */
		$byDay = [];
		foreach ($this->scalars->resolve($readings) as $reading) {
			$byDay[Timestamps::dayKey($reading->at, $this->display)][] = $reading->value;
		}
		ksort($byDay);

		$stats = [];
		foreach ($byDay as $day => $values) {
			$stats[] = new DailyStat(
				day: $day,
				min: min($values),
				max: max($values),
				mean: array_sum($values) / count($values),
				count: count($values),
			);
		}

		return $stats;
	}

	/**
	 * Every scalar reading in the window, oldest first — the raw series a trend
	 * line is drawn from.
	 *
	 * @return list<ScalarReading>
	 */
	public function scalarSeries(HealthMetric $metric, int $days = 90): array {
		$readings = [];
		foreach ($this->daysBackFromToday($days) as $day) {
			$readings = [...$readings, ...$this->scalarsOn($metric, $day)];
		}

		$resolved = $this->scalars->resolve($readings);
		usort($resolved, static fn (ScalarReading $a, ScalarReading $b): int => $a->at <=> $b->at);

		return $resolved;
	}

	/**
	 * Workouts in the window, most recent first.
	 *
	 * No deduplication at all, matching the phone. A workout is an event someone
	 * started, not a sample of a continuous signal, so two sources recording the
	 * same run are two records of it — and collapsing them would hide that a
	 * device was double-reporting.
	 *
	 * @return list<WorkoutReading>
	 */
	public function recentWorkouts(int $days = 30): array {
		$workouts = [];
		foreach ($this->daysBackFromToday($days) as $day) {
			foreach ($this->shards->readDay(HealthMetric::Activity, $day) as $point) {
				$workout = $this->parser->parseWorkout($point);
				if ($workout !== null) {
					$workouts[] = $workout;
				}
			}
		}
		usort($workouts, static fn (WorkoutReading $a, WorkoutReading $b): int
			=> $b->start <=> $a->start);

		return $workouts;
	}

	/** The most recent night, or `null` if none is in range. */
	public function lastNight(): ?NightSleep {
		return $this->lastNNights(1)[0] ?? null;
	}

	/**
	 * The last `$n` nights, most recent first.
	 *
	 * **Reads `$n + 2` calendar days, not `$n`.** Every other query here reads
	 * `days - 1` back from today; this one reads `n + 1` back. A night is filed
	 * under the date it *began*, and it usually begins the evening before, so
	 * asking for "last night" and reading only today would find the tail of a
	 * night whose onset segments live in yesterday's shard — and report a sleep
	 * that started at midnight.
	 *
	 * The asymmetry is inherited from the mobile reader and reproduced on
	 * purpose. It has a visible consequence worth knowing about: `isMainSleep`
	 * is decided across every episode in the window that shares a date, so a
	 * wider read can flip the flag on a boundary night. Normalising this to
	 * `days - 1` would look like a tidy-up and would make the two frontends
	 * disagree.
	 *
	 * @return list<NightSleep>
	 */
	public function lastNNights(int $n): array {
		/** @var list<SleepStageReading> $stages */
		$stages = [];
		/** @var list<SleepEpisodeReading> $episodes */
		$episodes = [];

		foreach ($this->daysBackFromToday($n + 2) as $day) {
			foreach ($this->shards->readDay(HealthMetric::Sleep, $day) as $point) {
				// The only place a schema name decides anything: two schemas
				// share the sleep shard. Namespace and version are ignored, and
				// any other name is dropped.
				match ($this->parser->schemaName($point)) {
					'sleep-stage' => $this->collect($stages, $this->parser->parseSleepStage($point)),
					'sleep-episode' => $this->collect($episodes, $this->parser->parseSleepEpisode($point)),
					default => null,
				};
			}
		}

		$nights = (new NightReconciler($this->display))->reconcile($stages, $episodes);
		usort($nights, static fn (NightSleep $a, NightSleep $b): int => $b->start <=> $a->start);

		return array_slice($nights, 0, $n);
	}

	/**
	 * Append `$value` to `$into` when it parsed.
	 *
	 * @param list<mixed> $into
	 */
	private function collect(array &$into, mixed $value): void {
		if ($value !== null) {
			$into[] = $value;
		}
	}

	/** @return list<ScalarReading> */
	private function scalarsOn(HealthMetric $metric, string $day): array {
		$readings = [];
		foreach ($this->shards->readDay($metric, $day) as $point) {
			$reading = $this->parser->parseScalar($point);
			if ($reading !== null) {
				$readings[] = $reading;
			}
		}

		return $readings;
	}

	/** @return list<\OCA\Cairn\Reading\Model\IntervalReading> */
	private function intervalsOn(HealthMetric $metric, string $day): array {
		$readings = [];
		foreach ($this->shards->readDay($metric, $day) as $point) {
			$reading = $this->parser->parseInterval($point);
			if ($reading !== null) {
				$readings[] = $reading;
			}
		}

		return $readings;
	}

	/** Today's local calendar date. */
	private function today(): string {
		return Timestamps::dayKey($this->clock->now(), $this->display);
	}

	/**
	 * `$days` calendar dates ending today, most recent first.
	 *
	 * Stepped by calendar date rather than by adding 24 hours, so a day on
	 * which the clocks change is still one day.
	 *
	 * @return list<string>
	 */
	private function daysBackFromToday(int $days): array {
		$cursor = new DateTimeImmutable($this->today(), $this->display);
		$out = [];
		for ($i = 0; $i < max(0, $days); $i++) {
			$out[] = $cursor->format('Y-m-d');
			$cursor = $cursor->modify('-1 day');
		}

		return $out;
	}
}
