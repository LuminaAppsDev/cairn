<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Test bootstrap.
 *
 * `lib/Reading/` needs nothing but Composer's autoloader — that is the point of
 * it. The classes in `lib/Service/` and `lib/Controller/` do touch Nextcloud,
 * and to mock an interface PHPUnit has to be able to load it.
 *
 * Those come from `nextcloud/ocp`, which ships the `OCP` API as PSR-4 sources
 * but declares no autoload section of its own — it is published for static
 * analysis rather than for running. Registering it here is what lets the unit
 * suite mock the server's own interfaces while still running anywhere `php`
 * does, with no Nextcloud installed.
 *
 * The package is pinned to the **lowest** Nextcloud the app claims, for the same
 * reason psalm analyses against it: a method that only exists in a later version
 * should fail here rather than on somebody's server. Whether the app works
 * against each real server is a different question, answered by
 * `nextcloud_app/dev matrix`.
 */

require_once __DIR__ . '/../vendor/autoload.php';

/*
 * A few `OCP` interfaces extend types in Nextcloud's private `OC\` namespace,
 * which the published stubs do not ship — `IRootFolder` extends
 * `OC\Hooks\Emitter`, for one. tests/stubs/ fills exactly those gaps and
 * nothing else; anything the app itself uses must come from `nextcloud/ocp`.
 */
spl_autoload_register(static function (string $class): void {
	if (!str_starts_with($class, 'OC\\')) {
		return;
	}
	$path = __DIR__ . '/stubs/' . str_replace('\\', '/', $class) . '.php';
	if (is_file($path)) {
		require_once $path;
	}
});

spl_autoload_register(static function (string $class): void {
	foreach (['OCP', 'NCU'] as $prefix) {
		if (!str_starts_with($class, $prefix . '\\')) {
			continue;
		}
		$path = __DIR__ . '/../vendor/nextcloud/ocp/'
			. str_replace('\\', '/', $class) . '.php';
		if (is_file($path)) {
			require_once $path;
		}

		return;
	}
});
