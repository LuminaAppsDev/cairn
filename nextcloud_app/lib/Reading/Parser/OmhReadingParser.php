<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Parser;

use DateTimeImmutable;
use DateTimeZone;
use OCA\Cairn\Reading\Json\StrictJson;
use OCA\Cairn\Reading\Json\Timestamps;
use OCA\Cairn\Reading\Model\IntervalReading;
use OCA\Cairn\Reading\Model\ReadingSource;
use OCA\Cairn\Reading\Model\ScalarReading;
use OCA\Cairn\Reading\Model\SleepEpisodeReading;
use OCA\Cairn\Reading\Model\SleepStage;
use OCA\Cairn\Reading\Model\SleepStageReading;
use OCA\Cairn\Reading\Model\WorkoutReading;

/**
 * Turns one decoded OMH datapoint into a reading, or into nothing.
 *
 * Total by construction: every method returns `null` for a missing or malformed
 * field rather than raising, so one damaged line can never take down a page. A
 * reading is produced only when every field it genuinely needs is present and of
 * the right JSON type.
 *
 * Note what does *not* decide which parser runs: the schema. Readings are
 * dispatched by the directory they were read from, exactly as on the phone, and
 * `header.schema_id.name` is consulted only inside `sleep/`, where two schemas
 * share a shard. Namespace and version are never examined at all — a stage line
 * written under a different namespace or a bumped version still parses, which is
 * what lets an older web app read a newer folder.
 */
final class OmhReadingParser {
	public function __construct(
		private readonly DateTimeZone $display,
	) {
	}

	/**
	 * `header.schema_id.name`, the only schema field the read path consults.
	 */
	public function schemaName(object $point): ?string {
		return StrictJson::str(
			StrictJson::obj(StrictJson::obj($point, 'header'), 'schema_id'),
			'name',
		);
	}

	/**
	 * A point-in-time reading — heart rate or body weight.
	 *
	 * Heart rate is tried first, so a body carrying both fields resolves the
	 * same way it does on the phone rather than by chance.
	 */
	public function parseScalar(object $point): ?ScalarReading {
		$body = StrictJson::obj($point, 'body');
		$measure = StrictJson::unitValue($body, 'heart_rate')
			?? StrictJson::unitValue($body, 'body_weight');
		$at = $this->pointTime($body);
		if ($measure === null || $at === null) {
			return null;
		}

		return new ScalarReading(
			value: $measure['value'],
			unit: $measure['unit'],
			at: $at,
			source: $this->provenance($point),
			ingestedAt: $this->ingestedAt($point),
		);
	}

	/** A step count over a window. */
	public function parseInterval(object $point): ?IntervalReading {
		$body = StrictJson::obj($point, 'body');
		$measure = StrictJson::unitValue($body, 'step_count');
		$window = $this->window($body);
		if ($measure === null || $window === null) {
			return null;
		}

		return new IntervalReading(
			value: $measure['value'],
			unit: $measure['unit'],
			start: $window[0],
			end: $window[1],
			source: $this->provenance($point),
			ingestedAt: $this->ingestedAt($point),
		);
	}

	/** A workout. Its stated `duration` is read past, never stored. */
	public function parseWorkout(object $point): ?WorkoutReading {
		$body = StrictJson::obj($point, 'body');
		$activity = StrictJson::str($body, 'activity_name');
		$window = $this->window($body);
		if ($activity === null || $window === null) {
			return null;
		}

		$steps = StrictJson::unitValue($body, 'base_movement_quantity');

		return new WorkoutReading(
			activityName: $activity,
			start: $window[0],
			end: $window[1],
			distanceMeters: StrictJson::unitValue($body, 'distance')['value'] ?? null,
			kcal: StrictJson::unitValue($body, 'kcal_burned')['value'] ?? null,
			// Half away from zero, matching Dart's `.round()`; a plain cast
			// would truncate and lose a step on every fractional count.
			steps: $steps === null ? null : (int)round($steps['value']),
			source: $this->provenance($point),
		);
	}

	/** One sleep-stage segment. An unknown stage drops the whole reading. */
	public function parseSleepStage(object $point): ?SleepStageReading {
		$body = StrictJson::obj($point, 'body');
		$stage = SleepStage::fromWire(StrictJson::str($body, 'sleep_stage'));
		$window = $this->window($body);
		if ($stage === null || $window === null) {
			return null;
		}

		return new SleepStageReading(
			stage: $stage,
			start: $window[0],
			end: $window[1],
			source: $this->provenance($point),
		);
	}

	/** A stored nightly rollup. */
	public function parseSleepEpisode(object $point): ?SleepEpisodeReading {
		$body = StrictJson::obj($point, 'body');
		$window = $this->window($body);
		$total = StrictJson::unitValue($body, 'total_sleep_time');
		if ($window === null || $total === null) {
			return null;
		}

		return new SleepEpisodeReading(
			start: $window[0],
			end: $window[1],
			totalSleepMillis: Timestamps::minutesToMillis($total['value']),
			// Identity against the JSON boolean: `"true" == true` in PHP.
			isMainSleep: StrictJson::isTrue($body, 'is_main_sleep'),
			awakenings: (int)round(StrictJson::num($body, 'number_of_awakenings') ?? 0.0),
			lightMillis: $this->durationMillis($body, 'light_sleep_duration'),
			deepMillis: $this->durationMillis($body, 'deep_sleep_duration'),
			remMillis: $this->durationMillis($body, 'rem_sleep_duration'),
			source: $this->provenance($point),
		);
	}

	/** When Cairn wrote this line, or `null` if the header did not say. */
	public function ingestedAt(object $point): ?DateTimeImmutable {
		return Timestamps::parse(
			StrictJson::str(StrictJson::obj($point, 'header'), 'creation_date_time'),
			$this->display,
		);
	}

	/**
	 * Provenance, or `null` — and `null` whenever *either* half is missing.
	 *
	 * This is the rule most likely to be ported wrong, because a line with a
	 * perfectly good `source_name` but no `modality` looks attributable and is
	 * not. Treating it as attributed would put it in its own dedup bucket here
	 * and in the unattributed bucket on the phone, so the same file would show
	 * a different number of readings in each frontend.
	 */
	public function provenance(object $point): ?ReadingSource {
		$block = StrictJson::obj(StrictJson::obj($point, 'header'), 'acquisition_provenance');
		$name = StrictJson::str($block, 'source_name');
		$modality = StrictJson::str($block, 'modality');
		if ($name === null || $modality === null) {
			return null;
		}

		return new ReadingSource(
			name: $name,
			modality: $modality,
			creationTime: Timestamps::parse(
				StrictJson::str($block, 'source_creation_date_time'),
				$this->display,
			),
		);
	}

	/** An `effective_time_frame.date_time` instant. */
	private function pointTime(?object $body): ?DateTimeImmutable {
		$frame = StrictJson::obj($body, 'effective_time_frame');

		return Timestamps::parse(StrictJson::str($frame, 'date_time'), $this->display);
	}

	/**
	 * An `effective_time_frame.time_interval` window.
	 *
	 * @return array{DateTimeImmutable, DateTimeImmutable}|null
	 */
	private function window(?object $body): ?array {
		$interval = StrictJson::obj(
			StrictJson::obj($body, 'effective_time_frame'),
			'time_interval',
		);
		$start = Timestamps::parse(StrictJson::str($interval, 'start_date_time'), $this->display);
		$end = Timestamps::parse(StrictJson::str($interval, 'end_date_time'), $this->display);
		if ($start === null || $end === null) {
			return null;
		}

		return [$start, $end];
	}

	/** An optional minutes-valued duration field, in milliseconds. */
	private function durationMillis(?object $body, string $field): ?int {
		$value = StrictJson::unitValue($body, $field);

		return $value === null ? null : Timestamps::minutesToMillis($value['value']);
	}
}
