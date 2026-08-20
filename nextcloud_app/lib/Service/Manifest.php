<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Service;

/**
 * What `/Cairn/manifest.json` says about the folder it sits in.
 *
 * The manifest is metadata, never authority: the shards are the data. A reader
 * that refused to work without a valid manifest would break on a folder that is
 * otherwise perfectly readable, so every field here is optional or defaulted.
 */
final class Manifest {
	/**
	 * @param array<string, string> $syncAnchors metric slug => ISO timestamp
	 * @param list<string>          $devices
	 */
	public function __construct(
		public readonly int $formatVersion,
		public readonly ?string $generator,
		public readonly ?string $updatedDateTime,
		public readonly array $syncAnchors,
		public readonly array $devices,
	) {
	}
}
