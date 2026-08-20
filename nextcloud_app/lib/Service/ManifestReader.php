<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Service;

use OCA\Cairn\Reading\Model\HealthMetric;

/**
 * Turns a decoded `manifest.json` into a {@see Manifest}.
 *
 * Pure by design — it takes an already-decoded object and touches no Nextcloud
 * API, so the parsing rules can be tested without a server.
 *
 * Typing is strict throughout, mirroring the mobile reader: a value of the wrong
 * JSON type is treated as absent rather than coerced. PHP would happily accept
 * `"1"` as an integer and `1` as a string; the Dart side would not, and two
 * frontends that disagree about the same bytes is the one failure this format
 * cannot tolerate (DESIGN.md §4.3).
 */
final class ManifestReader {
	/** What a manifest without a usable `format_version` is assumed to be. */
	public const DEFAULT_FORMAT_VERSION = 1;

	/**
	 * Parse a decoded manifest, or `null` if there was nothing to parse.
	 */
	public function parse(?object $raw): ?Manifest {
		if ($raw === null) {
			return null;
		}

		// Each field is read once into a local and then tested. Testing one
		// expression and returning another looks equivalent and is not: nothing
		// guarantees the second read sees what the first did.
		$formatVersion = $raw->format_version ?? null;
		$generator = $raw->generator ?? null;
		$updated = $raw->updated_date_time ?? null;

		return new Manifest(
			formatVersion: is_int($formatVersion)
				? $formatVersion
				: self::DEFAULT_FORMAT_VERSION,
			generator: is_string($generator) ? $generator : null,
			updatedDateTime: is_string($updated) ? $updated : null,
			syncAnchors: $this->syncAnchors($raw->sync_anchors ?? null),
			devices: $this->devices($raw->devices ?? null),
		);
	}

	/**
	 * Sync anchors for metrics this build knows about, dropping the rest.
	 *
	 * A newer mobile app may record anchors for metrics that do not exist here
	 * yet. Skipping them is what lets an older web app read a newer folder
	 * without complaint.
	 *
	 * @return array<string, string>
	 */
	private function syncAnchors(mixed $raw): array {
		if (!is_object($raw)) {
			return [];
		}

		$anchors = [];
		foreach (HealthMetric::all() as $metric) {
			$value = $raw->{$metric->value} ?? null;
			if (is_string($value)) {
				$anchors[$metric->value] = $value;
			}
		}

		return $anchors;
	}

	/**
	 * The recorded device names, ignoring any entry that is not a string.
	 *
	 * @return list<string>
	 */
	private function devices(mixed $raw): array {
		if (!is_array($raw)) {
			return [];
		}

		return array_values(array_filter($raw, 'is_string'));
	}
}
