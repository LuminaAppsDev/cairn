<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * A gap in the published stubs, filled here so the test suite can mock
 * `OCP\Files\IRootFolder`.
 *
 * `IRootFolder` extends this interface, but it lives in Nextcloud's private
 * `OC\` namespace and `nextcloud/ocp` ships only the public `OCP\` API — so
 * loading `IRootFolder` outside a server fails on a missing parent. Psalm hits
 * the same wall, which is why `psalm.xml` scopes a `MissingDependency`
 * suppression to the one file that holds a reference to it.
 *
 * Copied signature-for-signature from the server's own
 * `lib/private/Hooks/Emitter.php` so a mock implements what the real interface
 * requires. It is deprecated upstream in favour of `IEventDispatcher`, and this
 * app neither uses it nor implements it — it exists only so the type resolves.
 */

namespace OC\Hooks;

interface Emitter {
	/**
	 * @param string $scope
	 * @param string $method
	 *
	 * @return void
	 */
	public function listen($scope, $method, callable $callback);

	/**
	 * @param string $scope
	 * @param string $method
	 *
	 * @return void
	 */
	public function removeListener($scope = null, $method = null, ?callable $callback = null);
}
