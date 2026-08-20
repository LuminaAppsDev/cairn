<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Support;

use OCA\Cairn\Reading\Model\HealthMetric;
use OCA\Cairn\Reading\ShardSource;

/**
 * Reads a `/Cairn` folder straight off the filesystem.
 *
 * The counterpart to the server's storage-backed source, and the reason the
 * parity fixtures work at all: it takes exactly the same input the mobile
 * reader takes — a directory — so both frontends can be pointed at one folder
 * and asked the same questions.
 */
final class DirectoryShardSource implements ShardSource {
	public function __construct(
		private readonly string $root,
	) {
	}

	public function readDay(HealthMetric $metric, string $dayKey): array {
		$path = sprintf('%s/%s/%s/%s.jsonl', $this->root, $metric->value, substr($dayKey, 0, 4), $dayKey);
		if (!is_file($path)) {
			return [];
		}
		$contents = file_get_contents($path);
		if ($contents === false) {
			return [];
		}

		$points = [];
		foreach (explode("\n", $contents) as $line) {
			$trimmed = trim($line);
			if ($trimmed === '') {
				continue;
			}
			$decoded = json_decode($trimmed, false);
			if (is_object($decoded)) {
				$points[] = $decoded;
			}
		}

		return $points;
	}
}
