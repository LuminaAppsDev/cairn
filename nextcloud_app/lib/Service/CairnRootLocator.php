<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Service;

use OCP\Files\Folder;
use OCP\Files\IRootFolder;
use OCP\Files\NotFoundException;
use OCP\Files\NotPermittedException;

/**
 * Answers one question: is there a `/Cairn` folder in this user's storage?
 *
 * A missing folder is the ordinary state for anyone who has not run the mobile
 * app yet, so it is reported as `null` rather than raised as an error. This
 * class never creates the folder — the mobile app is the only writer
 * (DESIGN.md §7).
 */
final class CairnRootLocator {
	/** The folder the mobile app syncs into, at the root of the user's files. */
	public const ROOT_NAME = 'Cairn';

	public function __construct(
		private readonly IRootFolder $rootFolder,
	) {
	}

	/**
	 * The user's `/Cairn` folder, or `null` if it is absent or unreadable.
	 *
	 * Unreadable is treated exactly like absent: a permission problem on someone
	 * else's mount is not this app's business to report, and either way there is
	 * nothing to render.
	 */
	public function locate(string $userId): ?Folder {
		try {
			$node = $this->rootFolder->getUserFolder($userId)->get(self::ROOT_NAME);
		} catch (NotFoundException|NotPermittedException) {
			return null;
		}

		return $node instanceof Folder ? $node : null;
	}
}
