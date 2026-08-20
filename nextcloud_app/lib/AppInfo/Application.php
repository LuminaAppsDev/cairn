<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\AppInfo;

use OCP\AppFramework\App;
use OCP\AppFramework\Bootstrap\IBootContext;
use OCP\AppFramework\Bootstrap\IBootstrap;
use OCP\AppFramework\Bootstrap\IRegistrationContext;

/**
 * Application entry point.
 *
 * Deliberately almost empty. The navigation entry is declared in info.xml and
 * every service resolves through the container's autowiring, so there is no
 * registration to do — and nothing here that could acquire a write capability
 * by accident.
 */
class Application extends App implements IBootstrap {
	/** The app id, matching info.xml and the `cairn.` route prefix. */
	public const APP_ID = 'cairn';

	public function __construct() {
		parent::__construct(self::APP_ID);
	}

	public function register(IRegistrationContext $context): void {
	}

	public function boot(IBootContext $context): void {
	}
}
