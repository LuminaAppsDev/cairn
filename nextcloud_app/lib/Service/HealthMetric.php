<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Service;

/**
 * The metrics Cairn shards on disk, and the folder name each one uses.
 *
 * These strings are part of the on-disk format, not a display concern: they are
 * the directory names the mobile app writes (see `HealthMetric.slug` in
 * lib/src/health/health_metric.dart). Changing one is a breaking format change
 * requiring a `format_version` bump and a migration (DESIGN.md §5.4).
 */
enum HealthMetric: string {
	case HeartRate = 'heart-rate';
	case Steps = 'steps';
	case Sleep = 'sleep';
	case Activity = 'activity';
	case Weight = 'weight';

	/**
	 * Every metric, in the order the dashboard presents them.
	 *
	 * @return list<self>
	 */
	public static function all(): array {
		return [self::HeartRate, self::Steps, self::Sleep, self::Activity, self::Weight];
	}
}
