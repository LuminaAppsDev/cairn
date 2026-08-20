<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Proves, statically, that this app cannot write.
 *
 * WHY THIS EXISTS. "Read-only" is the app's entire contract (DESIGN.md §7): the
 * files in the user's Nextcloud are the system of record, and a second writer is
 * how a folder full of append-only shards turns into a folder full of conflict
 * copies. A contract asserted only in prose survives exactly as long as nobody
 * is in a hurry, so it is asserted here instead, where a review cannot miss it.
 *
 * Three rules, each of which has to hold for the guarantee to mean anything:
 *
 *   1. No mutating filesystem call appears anywhere in lib/.
 *   2. fopen() is never called in a mode other than read.
 *   3. OCP\Files\* is imported only by the two classes allowed to touch storage,
 *      so no Node, File or Folder handle can escape into code that might write
 *      through it.
 *
 * Deliberately dependency-free: plain PHP, no Composer, no PHPUnit, no server.
 * It runs anywhere `php` does, which means it can run before the dev environment
 * is even built. It is folded into the PHPUnit suite when that arrives.
 *
 * Run from this app's directory:  php tests/read_only_guard.php
 *
 * Exit status: 0 clean, 1 findings, 2 the check could not run.
 */

/** Only these files may speak to Nextcloud's filesystem API. */
const STORAGE_FILES = [
	'Service/CairnRootLocator.php',
	'Service/NextcloudShardSource.php',
];

/** Calls that write, move or delete. None of these belong in this app at all. */
const FORBIDDEN_CALLS = [
	'putContent', 'newFile', 'newFolder', 'delete', 'move', 'copy', 'touch',
	'file_put_contents', 'fwrite', 'fputs', 'unlink', 'rename', 'mkdir', 'rmdir',
	'rmDir', 'chmod', 'symlink', 'link', 'ftruncate',
];

$appRoot = dirname(__DIR__);
$libRoot = $appRoot . '/lib';
if (!is_dir($libRoot)) {
	fwrite(STDERR, "No lib/ directory at {$libRoot}.\n");
	fwrite(STDERR, "Run this from the app checkout: php tests/read_only_guard.php\n");
	exit(2);
}

/** @var list<string> $findings */
$findings = [];
$scanned = 0;

$files = new RegexIterator(
	new RecursiveIteratorIterator(new RecursiveDirectoryIterator($libRoot)),
	'/\.php$/',
);

/** @var SplFileInfo $file */
foreach ($files as $file) {
	$path = $file->getPathname();
	$relative = substr($path, strlen($libRoot) + 1);
	$source = file_get_contents($path);
	if ($source === false) {
		fwrite(STDERR, "Could not read {$path}.\n");
		exit(2);
	}
	$scanned++;

	foreach (explode("\n", $source) as $number => $line) {
		$where = $relative . ':' . ($number + 1);

		// Comments explain the rules; they must not be able to break them.
		$trimmed = ltrim($line);
		if ($trimmed === '' || str_starts_with($trimmed, '*') || str_starts_with($trimmed, '//')) {
			continue;
		}

		foreach (FORBIDDEN_CALLS as $call) {
			// Match a call, not a mention: the name followed by "(", optionally
			// preceded by "->" or "::".
			if (preg_match('/(?:->|::|\b)' . preg_quote($call, '/') . '\s*\(/', $line) === 1) {
				$findings[] = "{$where}: calls {$call}() — this app must never write.";
			}
		}

		if (preg_match('/fopen\s*\(\s*[^,]+,\s*(.)([^\'"]*)\1/', $line, $m) === 1) {
			$mode = $m[2];
			if ($mode !== 'r' && $mode !== 'rb') {
				$findings[] = "{$where}: fopen() in mode '{$mode}' — only 'r' and 'rb' are allowed.";
			}
		}

		if (preg_match('/^use\s+OCP\\\\Files\\\\/', $trimmed) === 1
			&& !in_array($relative, STORAGE_FILES, true)) {
			$findings[] = "{$where}: imports OCP\\Files — only "
				. implode(' and ', STORAGE_FILES) . ' may.';
		}
	}
}

// A glob that stops matching would turn this gate into a silent pass, which is
// worse than having no gate: it reports all-clear while checking nothing.
if ($scanned === 0) {
	fwrite(STDERR, "Scanned 0 files under {$libRoot}: the check proved nothing.\n");
	fwrite(STDERR, "This is a broken guard, not a clean result. Fix the traversal.\n");
	exit(2);
}

if ($findings !== []) {
	fwrite(STDERR, "Read-only guard failed:\n");
	foreach ($findings as $finding) {
		fwrite(STDERR, "  {$finding}\n");
	}
	exit(1);
}

echo "Read-only guard: {$scanned} files scanned, no write path found.\n";
exit(0);
