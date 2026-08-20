<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Service;

use OCA\Cairn\Reading\HealthQueryService;
use OCA\Cairn\Reading\Model\DailyStat;
use OCA\Cairn\Reading\Model\DailyValue;
use OCA\Cairn\Reading\Model\HealthMetric;
use OCA\Cairn\Reading\Model\NightSleep;
use OCA\Cairn\Reading\Model\ScalarReading;
use OCA\Cairn\Reading\Model\WorkoutReading;

/**
 * Shapes read-path results into the JSON the frontend consumes.
 *
 * Presentation only: no I/O, and no decisions about what the data *means* —
 * every rule that could make two readers disagree lives in `lib/Reading/` and is
 * pinned by the shared parity fixtures. What this class decides is narrower and
 * safe to differ: which fields a screen needs and what to call them.
 *
 * Durations are milliseconds and instants are ISO 8601 with an offset, matching
 * the parity encoding, so the wire format stays legible next to the fixtures.
 * Formatting for humans is the frontend's job, where the locale is known.
 */
final class DashboardAssembler {
	/** @return array<string, mixed> */
	public function steps(HealthQueryService $queries, int $days): array {
		$series = $queries->dailySteps($days);
		// Averaged over days that actually reported, not over the window: a day
		// with no sync is missing data, and folding it in as a zero would drag
		// the average down and make a gap look like inactivity.
		$reported = array_values(array_filter(
			$series,
			static fn (DailyValue $d): bool => $d->value > 0.0,
		));
		$total = array_sum(array_map(static fn (DailyValue $d): float => $d->value, $reported));

		return [
			'unit' => 'steps',
			'today' => $queries->todayStepTotal(),
			'average' => $reported === [] ? null : $total / (float)count($reported),
			'daysReported' => count($reported),
			'series' => array_map(
				static fn (DailyValue $d): array => ['day' => $d->day, 'value' => $d->value],
				$series,
			),
		];
	}

	/** @return array<string, mixed> */
	public function heartRate(HealthQueryService $queries, int $days): array {
		$series = $queries->dailyHeartRate($days);

		// Weighted by sample count. Averaging the daily means would give a day
		// with three readings the same say as one with three hundred.
		$samples = 0;
		$weighted = 0.0;
		$min = null;
		$max = null;
		foreach ($series as $stat) {
			$samples += $stat->count;
			$weighted += $stat->mean * (float)$stat->count;
			$min = $min === null ? $stat->min : min($min, $stat->min);
			$max = $max === null ? $stat->max : max($max, $stat->max);
		}

		return [
			'unit' => 'beats/min',
			'latest' => $this->scalar($queries->latestScalar(HealthMetric::HeartRate)),
			'min' => $min,
			'max' => $max,
			'mean' => $samples === 0 ? null : $weighted / (float)$samples,
			'samples' => $samples,
			'series' => array_map(
				static fn (DailyStat $s): array => [
					'day' => $s->day,
					'min' => $s->min,
					'max' => $s->max,
					'mean' => $s->mean,
					'count' => $s->count,
				],
				$series,
			),
		];
	}

	/** @return array<string, mixed> */
	public function weight(HealthQueryService $queries, int $days): array {
		$series = $queries->scalarSeries(HealthMetric::Weight, $days);
		$first = $series[0] ?? null;
		$last = $series === [] ? null : $series[count($series) - 1];

		return [
			'unit' => $last?->unit ?? 'kg',
			'latest' => $this->scalar($last),
			// Across the window that actually has readings, not the requested
			// span — otherwise the number silently means different things
			// depending on how much history exists.
			'change' => ($first === null || $last === null) ? null : $last->value - $first->value,
			'series' => array_map(
				static fn (ScalarReading $r): array => [
					'at' => $r->at->format('Y-m-d\TH:i:sP'),
					'day' => $r->at->format('Y-m-d'),
					'value' => $r->value,
				],
				$series,
			),
		];
	}

	/** @return array<string, mixed> */
	public function sleep(HealthQueryService $queries, int $nights): array {
		return [
			'nights' => array_map(
				fn (NightSleep $n): array => $this->night($n),
				$queries->lastNNights($nights),
			),
		];
	}

	/** @return array<string, mixed> */
	public function activity(HealthQueryService $queries, int $days): array {
		$workouts = $queries->recentWorkouts($days);

		return [
			'count' => count($workouts),
			'totalDurationMs' => array_sum(array_map(
				static fn (WorkoutReading $w): int => $w->durationMillis(),
				$workouts,
			)),
			'workouts' => array_map(
				static fn (WorkoutReading $w): array => [
					'activity' => $w->activityName,
					'start' => $w->start->format('Y-m-d\TH:i:sP'),
					'end' => $w->end->format('Y-m-d\TH:i:sP'),
					'durationMs' => $w->durationMillis(),
					'distanceM' => $w->distanceMeters,
					'kcal' => $w->kcal,
					'steps' => $w->steps,
					'source' => $w->source?->name,
				],
				$workouts,
			),
		];
	}

	/** @return array<string, mixed> */
	private function night(NightSleep $night): array {
		$sources = $night->sources;
		sort($sources);

		return [
			'night' => $night->night,
			'start' => $night->start->format('Y-m-d\TH:i:sP'),
			'end' => $night->end->format('Y-m-d\TH:i:sP'),
			'totalSleepMs' => $night->totalSleepMillis,
			'timeInBedMs' => $night->timeInBedMillis,
			'efficiency' => $night->efficiency,
			'awakenings' => $night->awakenings,
			'isMainSleep' => $night->isMainSleep,
			'hasStageBreakdown' => $night->hasStageBreakdown(),
			'perStageMs' => $night->perStageMillis,
			'sources' => $sources,
			// The segments themselves, so the frontend can draw a hypnogram
			// without a second request.
			'segments' => array_map(
				static fn ($segment): array => [
					'stage' => $segment->stage->value,
					'start' => $segment->start->format('Y-m-d\TH:i:sP'),
					'end' => $segment->end->format('Y-m-d\TH:i:sP'),
					'durationMs' => $segment->durationMillis(),
				],
				$night->stages,
			),
		];
	}

	/** @return array<string, mixed>|null */
	private function scalar(?ScalarReading $reading): ?array {
		if ($reading === null) {
			return null;
		}

		return [
			'value' => $reading->value,
			'unit' => $reading->unit,
			'at' => $reading->at->format('Y-m-d\TH:i:sP'),
			'source' => $reading->source?->name,
		];
	}
}
