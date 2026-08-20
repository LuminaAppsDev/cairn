<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Service;

use OCA\Cairn\Service\CairnRootLocator;
use OCA\Cairn\Tests\Support\BuildsStorage;
use PHPUnit\Framework\TestCase;

/**
 * One question: is there a `/Cairn` folder for this user?
 *
 * Every answer other than "yes" is `null`. A missing folder is the ordinary
 * state for anyone who has not run the phone app, and a folder that cannot be
 * read is somebody else's problem to report — either way there is nothing to
 * render, and distinguishing them here would only push the decision outward.
 */
final class CairnRootLocatorTest extends TestCase {
	use BuildsStorage;

	public function testFindsTheFolder(): void {
		$locator = new CairnRootLocator($this->storageWith(['manifest.json' => '{}']));

		self::assertNotNull($locator->locate('admin'));
	}

	public function testAMissingFolderIsNull(): void {
		$locator = new CairnRootLocator($this->storageWithoutCairn());

		self::assertNull($locator->locate('admin'));
	}

	/** Somebody could have a *file* called Cairn. It is not the folder. */
	public function testAFileNamedCairnIsNull(): void {
		$locator = new CairnRootLocator($this->storageWithCairnAsAFile());

		self::assertNull($locator->locate('admin'));
	}

	public function testAnUnknownUserIsNull(): void {
		$locator = new CairnRootLocator($this->storageWith(['manifest.json' => '{}']));

		self::assertNull($locator->locate('someone-else'));
	}
}
