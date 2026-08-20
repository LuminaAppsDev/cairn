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
 * A shard source backed by raw JSON-Lines text held in memory.
 *
 * Takes the same bytes a real shard holds, so tests exercise decoding and
 * line-skipping rather than hand-built objects — which is where the interesting
 * failures are. It also records which days were asked for, so a test can assert
 * the *window* a query reads, not only what it returns.
 */
final class InMemoryShardSource implements ShardSource {
	/** @var array<string, list<object>> */
	private array $shards = [];

	/** @var list<string> */
	public array $requestedDays = [];

	/** Add a shard from its raw file contents, malformed lines and all. */
	public function addRaw(HealthMetric $metric, string $dayKey, string $contents): self {
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
		$this->shards[$this->key($metric, $dayKey)] = $points;

		return $this;
	}

	/** Add a shard from datapoints given as JSON strings, one per line. */
	public function add(HealthMetric $metric, string $dayKey, string ...$lines): self {
		return $this->addRaw($metric, $dayKey, implode("\n", $lines));
	}

	public function readDay(HealthMetric $metric, string $dayKey): array {
		$this->requestedDays[] = $metric->value . '/' . $dayKey;

		return $this->shards[$this->key($metric, $dayKey)] ?? [];
	}

	/** The distinct dates asked for, for one metric, in ascending order. */
	public function daysReadFor(HealthMetric $metric): array {
		$prefix = $metric->value . '/';
		$days = [];
		foreach ($this->requestedDays as $entry) {
			if (str_starts_with($entry, $prefix)) {
				$days[substr($entry, strlen($prefix))] = true;
			}
		}
		$days = array_keys($days);
		sort($days);

		return $days;
	}

	private function key(HealthMetric $metric, string $dayKey): string {
		return $metric->value . '/' . $dayKey;
	}
}
