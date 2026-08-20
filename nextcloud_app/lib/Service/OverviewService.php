<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Service;

use OCA\Cairn\Reading\Model\HealthMetric;

/**
 * Surveys a user's `/Cairn` folder.
 *
 * The survey deliberately decodes the newest shard of each metric rather than
 * only counting files. Counting files proves the folder was listed; decoding
 * proves the bytes are readable and that a damaged line is survivable — which is
 * the property this skeleton exists to demonstrate before any of the read-path
 * semantics are ported.
 */
class OverviewService {
	public function __construct(
		private readonly NextcloudShardSource $shards,
		private readonly ManifestReader $manifestReader,
	) {
	}

	/** Survey `$userId`'s Cairn folder. */
	public function forUser(string $userId): Overview {
		if (!$this->shards->hasRoot($userId)) {
			return new Overview(hasRoot: false, manifest: null, metrics: []);
		}

		$metrics = [];
		foreach (HealthMetric::all() as $metric) {
			$metrics[] = $this->survey($userId, $metric);
		}

		return new Overview(
			hasRoot: true,
			manifest: $this->manifestReader->parse($this->shards->readRootJson($userId, 'manifest.json')),
			metrics: $metrics,
		);
	}

	/** Survey a single metric folder. */
	private function survey(string $userId, HealthMetric $metric): MetricOverview {
		$days = $this->shards->listShardDays($userId, $metric);
		if ($days === []) {
			return new MetricOverview($metric, 0, null, null, 0, 0);
		}

		$newest = $days[count($days) - 1];
		$reader = $this->shards->readShard($userId, $metric, $newest);
		$datapoints = 0;
		foreach ($reader as $_) {
			$datapoints++;
		}

		return new MetricOverview(
			metric: $metric,
			shardCount: count($days),
			firstDay: $days[0],
			lastDay: $newest,
			newestDatapoints: $datapoints,
			// Only meaningful once the generator has run to completion, which the
			// loop above guarantees.
			newestSkippedLines: $reader->getReturn(),
		);
	}
}
