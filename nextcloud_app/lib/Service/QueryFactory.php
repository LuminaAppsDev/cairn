<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Service;

use OCA\Cairn\Reading\HealthQueryService;
use OCA\Cairn\Reading\SystemClock;

/**
 * Builds a read path bound to one user.
 *
 * The pure layer takes its storage, its clock and its timezone as arguments and
 * knows nothing about Nextcloud. This is the single place those three are
 * supplied, so there is one answer to "which timezone are we in" rather than one
 * per caller — which is exactly the kind of drift that would make two screens of
 * the same app disagree about which day a reading belongs to.
 */
class QueryFactory {
	public function __construct(
		private readonly NextcloudShardSource $shards,
		private readonly DisplayTimeZone $timeZone,
	) {
	}

	public function forUser(string $userId): HealthQueryService {
		$display = $this->timeZone->get();

		return new HealthQueryService(
			shards: new UserShardSource($this->shards, $userId),
			clock: new SystemClock($display),
			display: $display,
		);
	}
}
