<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Support;

use DateTimeImmutable;
use DateTimeZone;
use OCA\Cairn\Reading\HealthQueryService;
use OCA\Cairn\Reading\Model\DailyStat;
use OCA\Cairn\Reading\Model\DailyValue;
use OCA\Cairn\Reading\Model\HealthMetric;
use OCA\Cairn\Reading\Model\NightSleep;
use OCA\Cairn\Reading\Model\ScalarReading;
use OCA\Cairn\Reading\Model\WorkoutReading;

/**
 * Runs a parity query and encodes the result in the shared wire form.
 *
 * The encoding is defined once in `test/fixtures/parity/README.md` and
 * implemented twice — here and in the Dart runner — so a difference between the
 * two suites is a real disagreement about the files rather than about
 * formatting. Every field is always present, so `null` means "no value" and
 * never "the key is missing".
 */
final class ParityEncoder {
	public function __construct(
		private readonly HealthQueryService $queries,
		private readonly DateTimeZone $display,
	) {
	}

	/**
	 * @param array<string, mixed> $query one entry from a spec's `queries`
	 *
	 * @throws \RuntimeException on a query name this reader does not implement
	 */
	public function run(array $query): mixed {
		$name = $query['name'];

		return match ($name) {
			'todayStepTotal' => $this->queries->todayStepTotal(),
			'dailySteps' => array_map(
				fn (DailyValue $d): array => ['day' => $d->day, 'value' => $d->value],
				$this->queries->dailySteps($this->intArg($query, 'days')),
			),
			'dailyHeartRate' => array_map(
				fn (DailyStat $s): array => [
					'day' => $s->day, 'min' => $s->min, 'max' => $s->max,
					'mean' => $s->mean, 'count' => $s->count,
				],
				$this->queries->dailyHeartRate($this->intArg($query, 'days')),
			),
			'latestScalar' => $this->scalar(
				$this->queries->latestScalar($this->metricArg($query)),
			),
			'scalarSeries' => array_map(
				fn (ScalarReading $r): array => [
					'value' => $r->value, 'at' => $this->instant($r->at),
				],
				$this->queries->scalarSeries(
					$this->metricArg($query),
					$this->intArg($query, 'days'),
				),
			),
			'recentWorkouts' => array_map(
				fn (WorkoutReading $w): array => [
					'activity' => $w->activityName,
					'start' => $this->instant($w->start),
					'end' => $this->instant($w->end),
					'durationMs' => $w->durationMillis(),
				],
				$this->queries->recentWorkouts($this->intArg($query, 'days')),
			),
			'lastNNights' => array_map(
				fn (NightSleep $n): array => $this->night($n),
				$this->queries->lastNNights($this->intArg($query, 'n')),
			),
			// Not a fallback: an unimplemented query must fail, so that adding
			// one to a fixture forces the other frontend to implement it too.
			default => throw new \RuntimeException(
				"parity query '{$name}' is not implemented by the PHP reader",
			),
		};
	}

	/** @return array<string, mixed>|null */
	private function scalar(?ScalarReading $reading): ?array {
		if ($reading === null) {
			return null;
		}

		return [
			'value' => $reading->value,
			'unit' => $reading->unit,
			'at' => $this->instant($reading->at),
			'source' => $reading->source?->name,
		];
	}

	/** @return array<string, mixed> */
	private function night(NightSleep $night): array {
		$sources = $night->sources;
		sort($sources);

		return [
			'night' => $night->night,
			'start' => $this->instant($night->start),
			'end' => $this->instant($night->end),
			'totalSleepMs' => $night->totalSleepMillis,
			'awakenings' => $night->awakenings,
			'isMainSleep' => $night->isMainSleep,
			'timeInBedMs' => $night->timeInBedMillis,
			'efficiency' => $night->efficiency,
			'sources' => $sources,
		];
	}

	private function instant(DateTimeImmutable $at): string {
		return $at->setTimezone($this->display)->format('Y-m-d\TH:i:sP');
	}

	/** @param array<string, mixed> $query */
	private function intArg(array $query, string $key): int {
		$value = $query[$key] ?? null;
		if (!is_int($value)) {
			throw new \RuntimeException("parity query needs an integer '{$key}'");
		}

		return $value;
	}

	/** @param array<string, mixed> $query */
	private function metricArg(array $query): HealthMetric {
		$slug = $query['metric'] ?? null;
		$metric = is_string($slug) ? HealthMetric::tryFrom($slug) : null;
		if ($metric === null) {
			throw new \RuntimeException('parity query needs a known "metric" slug');
		}

		return $metric;
	}
}
