<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

/*
 * Every route here is GET, and that is a design constraint rather than a
 * coincidence: this app is a read-only consumer of the user's own files
 * (DESIGN.md §7). A non-GET verb appearing in this list means something has
 * gone wrong, which makes the file itself a review checkpoint.
 */
return [
	'routes' => [
		['name' => 'page#index', 'url' => '/', 'verb' => 'GET'],
	],
];
