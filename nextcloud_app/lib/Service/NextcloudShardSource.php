<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Service;

use OCA\Cairn\Reading\Model\HealthMetric;
use OCP\Files\File;
use OCP\Files\Folder;
use OCP\Files\NotFoundException;
use OCP\Files\NotPermittedException;

/**
 * Reads the sharded JSON-Lines files under `/Cairn`.
 *
 * This is the only place the app touches Nextcloud's filesystem API, which is
 * what makes the read-only guarantee checkable rather than merely asserted: a
 * static test refuses any `OCP\Files\*` import outside this class and
 * {@see CairnRootLocator}, and refuses `fopen` in any mode but read here.
 * Nothing but plain decoded objects leaves these methods, so no `Node` handle
 * can reach code that might write through it.
 *
 * Shards live at `<slug>/<yyyy>/<yyyy-mm-dd>.jsonl` and are read line by line
 * rather than slurped: a year of heart-rate data is tens of thousands of lines,
 * and holding one day in memory is enough.
 *
 * Every method is total. A missing folder, an unreadable file, a truncated line
 * from an interrupted append — each is skipped, never raised. A single bad line
 * must never take down a page (DESIGN.md §4.3).
 */
class NextcloudShardSource {
	/**
	 * Shard days are exactly `YYYY-MM-DD`.
	 *
	 * Anchored with `\z` rather than `$`, which in PCRE also matches before a
	 * trailing newline — a distinction that costs nothing to get right and is
	 * the difference between a validator and a suggestion.
	 */
	private const DAY_PATTERN = '/^\d{4}-\d{2}-\d{2}\z/';

	/**
	 * The longest line this reader will buffer, in bytes.
	 *
	 * A shard is one JSON datapoint per line, a few hundred bytes at most. An
	 * unbounded `fgets()` would happily buffer a gigabyte-long line into memory
	 * and take the page down with it — and "only the mobile app writes here" is
	 * a design intention, not an enforced boundary: the folder is ordinary
	 * Nextcloud storage the user can sync anything into. Anything past this is
	 * damage by definition, so it is skipped like any other unusable line.
	 *
	 * Passed to `fgets()` as `MAX_LINE_BYTES + 1`, because `fgets($h, $n)` reads
	 * at most `$n - 1` bytes. Without the adjustment a line of exactly this
	 * length would come back without its newline, look over-long, and be
	 * discarded — so the constant would silently mean one byte less than it says.
	 */
	private const MAX_LINE_BYTES = 65536;

	public function __construct(
		private readonly CairnRootLocator $locator,
	) {
	}

	/**
	 * Whether this user has a `/Cairn` folder at all.
	 *
	 * Exists so callers can tell "no data yet" from "no folder yet" without ever
	 * handling a `Folder`, which is what keeps the filesystem API confined to
	 * this class.
	 */
	public function hasRoot(string $userId): bool {
		return $this->locator->locate($userId) !== null;
	}

	/**
	 * The dates for which `$metric` has a shard, ascending.
	 *
	 * @return list<string> ISO `YYYY-MM-DD` dates
	 */
	public function listShardDays(string $userId, HealthMetric $metric): array {
		$metricFolder = $this->childFolder($this->locator->locate($userId), $metric->value);
		if ($metricFolder === null) {
			return [];
		}

		$days = [];
		foreach ($this->folderChildren($metricFolder) as $yearNode) {
			// Year folders only; anything else in here is not ours to interpret.
			if (!$yearNode instanceof Folder) {
				continue;
			}
			foreach ($this->folderChildren($yearNode) as $shard) {
				if (!$shard instanceof File) {
					continue;
				}
				$day = basename($shard->getName(), '.jsonl');
				if ($day !== $shard->getName() && $this->isShardDay($day)) {
					$days[] = $day;
				}
			}
		}
		sort($days);

		return $days;
	}

	/**
	 * Decode one shard, yielding a decoded object per usable line.
	 *
	 * Lines are decoded to `stdClass`, not to associative arrays. That is not a
	 * style choice: `json_decode($line, true)` renders `{}` and `[]`
	 * indistinguishable and silently coerces numeric object keys to integers,
	 * whereas the mobile reader accepts a line only if it is a JSON *object*
	 * (`decoded is Map<String, dynamic>`). Decoding to an object reproduces that
	 * test exactly.
	 *
	 * The generator's return value is the number of lines that were skipped, so
	 * a caller can surface "3 unreadable lines" instead of quietly under-reporting.
	 * Read it with `$generator->getReturn()` once iteration has finished.
	 *
	 * @return \Generator<int, object, mixed, int>
	 */
	public function readShard(string $userId, HealthMetric $metric, string $day): \Generator {
		// Validated here rather than trusted from the caller. Today `$day` only
		// ever comes from listShardDays(), which already pattern-matched it —
		// but this method is one "show me a specific day" feature away from
		// taking a request parameter, and a `../` in it would then walk out of
		// the metric folder. Making the method safe on its own terms costs one
		// line and removes the need for every future caller to remember.
		if (!$this->isShardDay($day)) {
			return 0;
		}

		$root = $this->locator->locate($userId);
		$metricFolder = $this->childFolder($root, $metric->value);
		$yearFolder = $this->childFolder($metricFolder, substr($day, 0, 4));
		if ($yearFolder === null) {
			return 0;
		}

		try {
			$shard = $yearFolder->get($day . '.jsonl');
		} catch (NotFoundException | NotPermittedException) {
			return 0;
		}
		if (!$shard instanceof File) {
			return 0;
		}

		try {
			$handle = $shard->fopen('r');
		} catch (NotPermittedException) {
			return 0;
		}
		if (!is_resource($handle)) {
			return 0;
		}

		$skipped = 0;
		try {
			while (($line = fgets($handle, self::MAX_LINE_BYTES + 1)) !== false) {
				// A chunk that did not end at a newline means the line is longer
				// than the cap. Discard the remainder without ever holding it,
				// and count the whole thing as one unusable line rather than as
				// one per chunk.
				if (!str_ends_with($line, "\n") && !feof($handle)) {
					$this->discardRestOfLine($handle);
					$skipped++;
					continue;
				}

				$trimmed = trim($line);
				if ($trimmed === '') {
					// Blank lines are separators, not damage — not counted.
					continue;
				}
				$decoded = json_decode($trimmed, false);
				// A torn trailing append, or valid JSON that is not an object
				// (an array, a bare number), lands here and is skipped —
				// matching the mobile reader line for line.
				if (is_object($decoded)) {
					yield $decoded;
				} else {
					$skipped++;
				}
			}
		} finally {
			fclose($handle);
		}

		return $skipped;
	}

	/** Whether `$day` is a well-formed `YYYY-MM-DD` shard day. */
	private function isShardDay(string $day): bool {
		return preg_match(self::DAY_PATTERN, $day) === 1;
	}

	/**
	 * Advance past the rest of an over-long line, holding only one chunk at a time.
	 *
	 * @param resource $handle
	 */
	private function discardRestOfLine($handle): void {
		while (!feof($handle)) {
			$chunk = fgets($handle, self::MAX_LINE_BYTES + 1);
			if ($chunk === false || str_ends_with($chunk, "\n")) {
				return;
			}
		}
	}

	/**
	 * Decode a JSON file sitting directly in `/Cairn`, such as `manifest.json`.
	 *
	 * Returns `null` when the file is absent, unreadable, not valid JSON, or not
	 * a JSON object. Parsing it into something meaningful is somebody else's
	 * job — this method exists so that job can be done without a server.
	 */
	public function readRootJson(string $userId, string $name): ?object {
		$root = $this->locator->locate($userId);
		if ($root === null) {
			return null;
		}

		try {
			$file = $root->get($name);
			if (!$file instanceof File) {
				return null;
			}
			$decoded = json_decode($file->getContent(), false);
		} catch (NotFoundException | NotPermittedException | \OCP\Files\GenericFileException | \OCP\Lock\LockedException) {
			return null;
		}

		return is_object($decoded) ? $decoded : null;
	}

	/**
	 * A named subfolder of `$parent`, or `null` if it is absent or not a folder.
	 */
	private function childFolder(?Folder $parent, string $name): ?Folder {
		if ($parent === null) {
			return null;
		}
		try {
			$node = $parent->get($name);
		} catch (NotFoundException | NotPermittedException) {
			return null;
		}

		return $node instanceof Folder ? $node : null;
	}

	/**
	 * The children of `$folder`, or nothing at all if it cannot be listed.
	 *
	 * @return list<\OCP\Files\Node>
	 */
	private function folderChildren(Folder $folder): array {
		try {
			return $folder->getDirectoryListing();
		} catch (NotFoundException | NotPermittedException) {
			return [];
		}
	}
}
