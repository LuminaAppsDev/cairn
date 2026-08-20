<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Json;

/**
 * Field accessors that refuse to guess.
 *
 * The mobile reader checks JSON types exactly — `value is num`, `value is String`
 * — and treats a mismatch as a missing field. PHP's instinct is the opposite: it
 * will happily read `"62"` as a number and `62` as a string, and every one of
 * those conversions is a place where the two frontends would quietly disagree
 * about the same bytes. DESIGN.md §4.3 makes that the one thing this format
 * cannot tolerate, so every accessor here is strict and returns `null` rather
 * than converting.
 *
 * Values come from `json_decode($line, false)`, so JSON objects arrive as
 * `stdClass` and JSON arrays as PHP arrays. That distinction is deliberate:
 * decoding to associative arrays would make `{}` and `[]` indistinguishable,
 * which is precisely the test the mobile reader applies to every line.
 */
final class StrictJson {
	/** A nested JSON object, or `null` if absent or not an object. */
	public static function obj(?object $source, string $key): ?object {
		$value = $source?->{$key} ?? null;

		return is_object($value) ? $value : null;
	}

	/** A JSON string, or `null`. A number is not a string. */
	public static function str(?object $source, string $key): ?string {
		$value = $source?->{$key} ?? null;

		return is_string($value) ? $value : null;
	}

	/**
	 * A JSON number as a float, or `null`.
	 *
	 * `is_int() || is_float()` rather than `is_numeric()`: the latter accepts the
	 * string `"62"`, which the mobile reader rejects. Booleans are not numbers
	 * either, in both readers.
	 */
	public static function num(?object $source, string $key): ?float {
		$value = $source?->{$key} ?? null;

		return (is_int($value) || is_float($value)) ? (float)$value : null;
	}

	/**
	 * Whether a field is JSON `true`, specifically.
	 *
	 * Identity, not equality: PHP's `==` makes the *string* `"true"` equal to
	 * `true`, so a source that emits `"is_main_sleep": "true"` would be read as
	 * a main sleep here and as a non-main sleep on the phone.
	 */
	public static function isTrue(?object $source, string $key): bool {
		return ($source?->{$key} ?? null) === true;
	}

	/**
	 * An OMH unit-value pair — `{"value": 62, "unit": "beats/min"}`.
	 *
	 * The unit is mandatory. A unit-value missing it is dropped whole, which in
	 * turn drops any reading that required it: units come from the schema and a
	 * reading whose unit is unknown is not one this app is willing to guess at
	 * (DESIGN.md §5.2). No conversion is ever applied; the unit is carried
	 * through verbatim.
	 *
	 * @return array{value: float, unit: string}|null
	 */
	public static function unitValue(?object $body, string $field): ?array {
		$pair = self::obj($body, $field);
		if ($pair === null) {
			return null;
		}
		$value = self::num($pair, 'value');
		$unit = self::str($pair, 'unit');
		if ($value === null || $unit === null) {
			return null;
		}

		return ['value' => $value, 'unit' => $unit];
	}
}
