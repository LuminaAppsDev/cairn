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
 *
 * No route takes a user id either — each request is scoped to whoever is logged
 * in, so there is no id to swap for somebody else's.
 */
return [
	'routes' => [
		['name' => 'page#index', 'url' => '/', 'verb' => 'GET'],

		['name' => 'api#files', 'url' => '/api/v1/files', 'verb' => 'GET'],
		['name' => 'api#steps', 'url' => '/api/v1/steps', 'verb' => 'GET'],
		['name' => 'api#heartRate', 'url' => '/api/v1/heart-rate', 'verb' => 'GET'],
		['name' => 'api#weight', 'url' => '/api/v1/weight', 'verb' => 'GET'],
		['name' => 'api#sleep', 'url' => '/api/v1/sleep', 'verb' => 'GET'],
		['name' => 'api#activity', 'url' => '/api/v1/activity', 'verb' => 'GET'],
	],
];
