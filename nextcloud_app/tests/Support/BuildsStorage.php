<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Support;

use OCP\Files\File;
use OCP\Files\Folder;
use OCP\Files\IRootFolder;
use OCP\Files\Node;
use OCP\Files\NotFoundException;

/**
 * Builds a Nextcloud storage tree out of test doubles.
 *
 * The classes that touch `OCP\Files` are the app's only contact with the
 * server, and until now they were exercised only end-to-end — by the
 * compatibility matrix and the packaged-app check, which prove the whole thing
 * works but say nothing about *which* branch handled a missing folder or a torn
 * line. This is what lets those branches be tested one at a time, with no
 * server involved.
 *
 * A tree is written the way it looks on disk:
 *
 *     $this->storageWith(['steps/2026/2026-08-20.jsonl' => "{...}\n"])
 *
 * Files are backed by real in-memory streams, so `fopen()` and the line reader
 * behave exactly as they do against Nextcloud — including the byte cap.
 *
 * These are stubs rather than mocks on purpose: the tests care what the storage
 * *returns*, never how many times it was asked. A mock here would assert
 * interactions nobody is interested in and fail whenever the reader is made
 * more efficient.
 */
trait BuildsStorage {
	/**
	 * A root folder whose `/Cairn` contains `$tree`.
	 *
	 * @param array<string, string> $tree path under `/Cairn` => file contents
	 */
	protected function storageWith(array $tree, string $userId = 'admin'): IRootFolder {
		return $this->rootReturning($this->folderFromTree($tree), $userId);
	}

	/**
	 * A root folder with no `/Cairn` in it — the ordinary state for anyone who
	 * has not run the phone app yet.
	 */
	protected function storageWithoutCairn(string $userId = 'admin'): IRootFolder {
		$userFolder = $this->createStub(Folder::class);
		$userFolder->method('get')
			->willThrowException(new NotFoundException('Cairn'));

		return $this->rootWithUserFolder($userFolder, $userId);
	}

	/** A root folder whose `/Cairn` is a file rather than a folder. */
	protected function storageWithCairnAsAFile(string $userId = 'admin'): IRootFolder {
		return $this->rootReturning($this->fileNamed('Cairn', ''), $userId);
	}

	private function rootReturning(Node $cairn, string $userId): IRootFolder {
		$userFolder = $this->createStub(Folder::class);
		$userFolder->method('get')->willReturnCallback(
			static function (string $name) use ($cairn): Node {
				if ($name !== 'Cairn') {
					throw new NotFoundException($name);
				}

				return $cairn;
			},
		);

		return $this->rootWithUserFolder($userFolder, $userId);
	}

	/**
	 * A root that knows about exactly one user.
	 *
	 * Asking for anyone else throws, as the real one does — so a test that
	 * accidentally reads somebody else's files fails rather than quietly
	 * getting these.
	 */
	private function rootWithUserFolder(Folder $userFolder, string $userId): IRootFolder {
		$root = $this->createStub(IRootFolder::class);
		$root->method('getUserFolder')->willReturnCallback(
			static function (string $uid) use ($userFolder, $userId): Folder {
				if ($uid !== $userId) {
					throw new NotFoundException("no such user: {$uid}");
				}

				return $userFolder;
			},
		);

		return $root;
	}

	/**
	 * @param array<array-key, string> $tree
	 */
	private function folderFromTree(array $tree): Folder {
		return $this->folderContaining($this->nodesFromTree($tree));
	}

	/**
	 * @param array<array-key, string> $tree
	 *
	 * @return array<array-key, Node>
	 */
	private function nodesFromTree(array $tree): array {
		// array-key, not string: PHP turns a numeric-looking key into an
		// integer, so a year folder named "2026" arrives here as int 2026 —
		// the same coercion StrictJson exists to avoid, met in a test helper.
		/** @var array<array-key, array<array-key, string>> $children */
		$children = [];
		/** @var array<array-key, string> $files */
		$files = [];

		foreach ($tree as $path => $contents) {
			$slash = strpos($path, '/');
			if ($slash === false) {
				$files[$path] = $contents;
				continue;
			}
			$children[substr($path, 0, $slash)][substr($path, $slash + 1)] = $contents;
		}

		$nodes = [];
		foreach ($files as $name => $contents) {
			$nodes[(string)$name] = $this->fileNamed((string)$name, $contents);
		}
		foreach ($children as $name => $subtree) {
			$nodes[(string)$name] = $this->folderContaining(
				$this->nodesFromTree($subtree),
				(string)$name,
			);
		}

		return $nodes;
	}

	/**
	 * A folder stub holding `$nodes`, named if it is a child rather than the
	 * root. Named on construction rather than afterwards, so the helper's
	 * return type can stay `Folder` instead of leaking the stub back out.
	 *
	 * @param array<array-key, Node> $nodes
	 */
	private function folderContaining(array $nodes, ?string $name = null): Folder {
		$folder = $this->createStub(Folder::class);
		if ($name !== null) {
			$folder->method('getName')->willReturn($name);
		}
		$folder->method('get')->willReturnCallback(
			static function (string $name) use ($nodes): Node {
				if (!array_key_exists($name, $nodes)) {
					throw new NotFoundException($name);
				}

				return $nodes[$name];
			},
		);
		// Keyed, not a list — which is what the real API returns, and what
		// NextcloudShardSource has to re-index.
		$folder->method('getDirectoryListing')->willReturn($nodes);

		return $folder;
	}

	private function fileNamed(string $name, string $contents): File {
		$file = $this->createStub(File::class);
		$file->method('getName')->willReturn($name);
		$file->method('getContent')->willReturn($contents);
		// A real stream, so the reader's fgets loop and byte cap are exercised
		// rather than stubbed past.
		$file->method('fopen')->willReturnCallback(
			static function (string $mode) use ($contents) {
				$handle = fopen('php://memory', 'r+');
				if ($handle === false) {
					return false;
				}
				fwrite($handle, $contents);
				rewind($handle);

				return $handle;
			},
		);

		return $file;
	}
}
