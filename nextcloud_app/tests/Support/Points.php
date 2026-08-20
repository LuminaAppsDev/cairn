<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Support;

/**
 * Builders for raw OMH datapoint lines, shaped exactly like a real export's.
 *
 * Tests feed the query service the bytes a shard actually holds rather than
 * pre-built objects, so parsing, line-skipping and resolution are all exercised
 * by the same test.
 */
final class Points {
	/** The source in the real export; matches no wearable fragment. */
	public const VENDOR = 'com.sec.android.app.shealth';
	/** Contains "fit", so it outranks the vendor app. */
	public const WEARABLE = 'Galaxy Fit3';
	/** Health Connect's own per-interval records. */
	public const PLATFORM = 'android';

	private static function header(
		string $name,
		string $version,
		?string $ingested,
		?string $source,
		string $namespace = 'omh',
		string $modality = 'sensed',
	): string {
		$parts = ['"id":"' . bin2hex(random_bytes(8)) . '"'];
		if ($ingested !== null) {
			$parts[] = '"creation_date_time":"' . self::iso($ingested) . '"';
		}
		$parts[] = '"schema_id":{"namespace":"' . $namespace . '","name":"' . $name
			. '","version":"' . $version . '"}';
		if ($source !== null) {
			$parts[] = '"acquisition_provenance":{"source_name":"' . $source
				. '","modality":"' . $modality . '"}';
		}

		return '"header":{' . implode(',', $parts) . '}';
	}

	/** `2026-08-20 06:19` or `06:19` (assumed 2026-08-20) to a full ISO stamp. */
	public static function iso(string $when): string {
		$value = str_contains($when, '-') ? $when : "2026-08-20 {$when}";

		return (new \DateTimeImmutable($value, Readings::zone()))->format('Y-m-d\TH:i:sP');
	}

	public static function heartRate(
		float $value,
		string $at,
		?string $ingested = null,
		?string $source = self::VENDOR,
	): string {
		return '{' . self::header('heart-rate', '1.0', $ingested, $source)
			. ',"body":{"heart_rate":{"value":' . $value . ',"unit":"beats/min"},'
			. '"effective_time_frame":{"date_time":"' . self::iso($at) . '"}}}';
	}

	public static function weight(
		float $value,
		string $at,
		?string $ingested = null,
		?string $source = self::VENDOR,
	): string {
		return '{' . self::header('body-weight', '2.0', $ingested, $source)
			. ',"body":{"body_weight":{"value":' . $value . ',"unit":"kg"},'
			. '"effective_time_frame":{"date_time":"' . self::iso($at) . '"}}}';
	}

	public static function steps(
		float $value,
		string $start,
		string $end,
		?string $ingested = null,
		?string $source = self::VENDOR,
	): string {
		return '{' . self::header('step-count', '3.0', $ingested, $source)
			. ',"body":{"step_count":{"value":' . $value . ',"unit":"steps"},'
			. '"effective_time_frame":{"time_interval":{"start_date_time":"' . self::iso($start)
			. '","end_date_time":"' . self::iso($end) . '"}}}}';
	}

	public static function workout(
		string $activity,
		string $start,
		string $end,
		?string $source = self::VENDOR,
	): string {
		return '{' . self::header('physical-activity', '1.0', null, $source)
			. ',"body":{"activity_name":"' . $activity . '",'
			. '"effective_time_frame":{"time_interval":{"start_date_time":"' . self::iso($start)
			. '","end_date_time":"' . self::iso($end) . '"}},'
			. '"duration":{"value":999.0,"unit":"min"}}}';
	}

	public static function sleepStage(
		string $stage,
		string $start,
		string $end,
		?string $source = self::VENDOR,
		string $modality = 'sensed',
	): string {
		return '{' . self::header('sleep-stage', '1.0', null, $source, 'cairn', $modality)
			. ',"body":{"sleep_stage":"' . $stage . '",'
			. '"effective_time_frame":{"time_interval":{"start_date_time":"' . self::iso($start)
			. '","end_date_time":"' . self::iso($end) . '"}}}}';
	}

	public static function sleepEpisode(
		string $start,
		string $end,
		float $totalMinutes,
	): string {
		return '{' . self::header('sleep-episode', '1.0', null, self::VENDOR)
			. ',"body":{"effective_time_frame":{"time_interval":{"start_date_time":"'
			. self::iso($start) . '","end_date_time":"' . self::iso($end) . '"}},'
			. '"total_sleep_time":{"value":' . $totalMinutes . ',"unit":"min"},'
			. '"is_main_sleep":true,"number_of_awakenings":99}}';
	}
}
