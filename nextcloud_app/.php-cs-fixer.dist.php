<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Nextcloud's own coding standard, for the same reason the Vite and ESLint
 * configs use theirs: this code runs inside their server and is read by people
 * who work on their apps. A house style here would be one more thing for a
 * contributor to learn and one more way to drift from the platform.
 */

require_once __DIR__ . '/vendor/autoload.php';

use Nextcloud\CodingStandard\Config;

$config = new Config();
$config
	->getFinder()
	->in(__DIR__ . '/lib')
	->in(__DIR__ . '/tests')
	->notPath('vendor');

return $config;
