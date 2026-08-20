<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Reading\Model;

use DateTimeImmutable;

/**
 * Where a reading came from, parsed from `header.acquisition_provenance`.
 *
 * Provenance is all-or-nothing on purpose, mirroring the mobile reader: without
 * *both* a source name and a modality there is no source at all, not a partial
 * one. That is not fussiness — the dedup rules key on the source, and a reading
 * with a name but no modality must fall in the same bucket as a completely
 * unattributed one or the two frontends part company on the same file.
 */
final class ReadingSource {
	public function __construct(
		public readonly string $name,
		public readonly string $modality,
		public readonly ?DateTimeImmutable $creationTime = null,
	) {
	}

	/**
	 * Whether this reading was typed in by hand rather than sensed.
	 *
	 * Compared against the exact OMH spelling; anything else — including
	 * `sensed` — counts as automatic.
	 */
	public function isManual(): bool {
		return $this->modality === 'self-reported';
	}
}
