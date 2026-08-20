<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Service;

use OCA\Cairn\Reading\Model\HealthMetric;
use OCA\Cairn\Reading\ShardSource;

/**
 * Binds a user to the storage, so the read path never has to know about users.
 *
 * The pure {@see ShardSource} contract deliberately has no notion of *whose*
 * files these are — that keeps it testable against a plain directory and
 * comparable with the mobile reader, which only ever has one user. This adapter
 * is where the two meet, and it is the only place a uid appears below the
 * controller.
 */
final class UserShardSource implements ShardSource {
	public function __construct(
		private readonly NextcloudShardSource $shards,
		private readonly string $userId,
	) {
	}

	public function readDay(HealthMetric $metric, string $dayKey): array {
		// Materialised rather than streamed onward: the pure layer resolves a
		// day as a whole — it has to compare every line against every other to
		// deduplicate — so there is nothing to gain by keeping it lazy, and a
		// plain list is what the contract promises.
		return iterator_to_array($this->shards->readShard($this->userId, $metric, $dayKey), false);
	}
}
