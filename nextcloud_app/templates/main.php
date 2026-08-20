<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * The page shell.
 *
 * Everything visible is rendered by the Vue app that mounts into the div below.
 * The only thing the server puts on the page directly is whether a `/Cairn`
 * folder exists at all — provided as initial state so the "connect the phone
 * app" case paints immediately, instead of after five requests have each come
 * back empty.
 *
 * @var array{hasRoot: bool} $_
 */

\OCP\Util::addScript('cairn', 'cairn-main');
?>
<div id="cairn"></div>
