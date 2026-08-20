<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Validates appinfo/info.xml against the Nextcloud app store's schema.
 *
 * WHY THIS EXISTS. info.xml is the one file whose mistakes are invisible until
 * they are expensive. A misordered element or an unknown licence identifier is
 * rejected at upload time, long after the release is cut; a stale
 * `max-version` is worse still, because it fails silently on somebody else's
 * server when they upgrade Nextcloud and the app simply disappears
 * (DESIGN.md §7).
 *
 * Beyond schema conformance it asserts the facts the schema cannot know: that
 * the licence really is the AGPL this subtree ships under (docs/DEVELOPMENT.md
 * §5); that the app declares no write surface — background jobs, repair steps,
 * commands and Sabre plugins are all ways an app acquires the ability to change
 * things, and this one has none; and that the published contact and links point
 * at the project rather than at a person or a fork.
 *
 * The schema is fetched once and cached beside this script, so the check works
 * offline afterwards and cannot fail a build because a website was down.
 *
 * Run from this app's directory:  php tests/validate_info_xml.php
 *
 * Exit status: 0 clean, 1 findings, 2 the check could not run.
 */

const SCHEMA_URL = 'https://apps.nextcloud.com/schema/apps/info.xsd';
const SCHEMA_CACHE = __DIR__ . '/fixtures/info.xsd';

/**
 * The address the app store shows to everyone who installs this.
 *
 * Asserted because the failure is silent and permanent: a personal address that
 * slips back in is published to every self-hoster, and cannot be recalled from
 * the releases that already carry it. Releases go out from the LuminaAppsDev
 * account, so the contact belongs to the project.
 */
const AUTHOR_CONTACT = 'luminaapps@gmail.com';

/** Where issues are reported. Must be the project's repository, not a fork. */
const PROJECT_HOST = 'github.com/LuminaAppsDev/cairn';

/** Elements through which an app gains a way to write. None may appear. */
const WRITE_SURFACE = [
	'background-jobs', 'repair-steps', 'commands', 'sabre', 'settings',
];

if (!class_exists(DOMDocument::class)) {
	fwrite(STDERR, "PHP has no DOM extension, so the schema cannot be validated.\n");
	fwrite(STDERR, "Run this inside the dev container: nextcloud_app/dev check\n");
	exit(2);
}

$appRoot = dirname(__DIR__);
$infoPath = $appRoot . '/appinfo/info.xml';
if (!is_file($infoPath)) {
	fwrite(STDERR, "No appinfo/info.xml at {$infoPath}.\n");
	fwrite(STDERR, "Run this from the app checkout: php tests/validate_info_xml.php\n");
	exit(2);
}

$schema = is_file(SCHEMA_CACHE) ? file_get_contents(SCHEMA_CACHE) : false;
if ($schema === false) {
	$schema = @file_get_contents(SCHEMA_URL);
	if ($schema === false) {
		fwrite(STDERR, 'No cached schema at ' . SCHEMA_CACHE . ' and ' . SCHEMA_URL . " is unreachable.\n");
		fwrite(STDERR, "Fetch it once with network access, then commit it.\n");
		exit(2);
	}
	@mkdir(dirname(SCHEMA_CACHE), 0o755, true);
	file_put_contents(SCHEMA_CACHE, $schema);
}

libxml_use_internal_errors(true);
$document = new DOMDocument();
if ($document->load($infoPath) === false) {
	fwrite(STDERR, "appinfo/info.xml is not well-formed XML:\n");
	foreach (libxml_get_errors() as $error) {
		fwrite(STDERR, '  ' . trim($error->message) . "\n");
	}
	exit(1);
}

/** @var list<string> $findings */
$findings = [];

if (!$document->schemaValidateSource($schema)) {
	foreach (libxml_get_errors() as $error) {
		$findings[] = 'schema: ' . trim($error->message);
	}
}

$root = $document->documentElement;
if ($root === null) {
	fwrite(STDERR, "appinfo/info.xml has no root element.\n");
	exit(1);
}

$licences = [];
foreach ($root->getElementsByTagName('licence') as $licence) {
	$licences[] = $licence->textContent;
}
if ($licences !== ['AGPL-3.0-or-later']) {
	$findings[] = 'licence: expected exactly AGPL-3.0-or-later, found '
		. ($licences === [] ? 'none' : implode(', ', $licences))
		. ' — see docs/DEVELOPMENT.md §5.';
}

$authors = $root->getElementsByTagName('author');
if ($authors->length === 0) {
	$findings[] = 'author: none declared.';
} else {
	foreach ($authors as $author) {
		if (!$author instanceof DOMElement) {
			continue;
		}
		$mail = $author->getAttribute('mail');
		if ($mail !== AUTHOR_CONTACT) {
			$findings[] = "author: contact is '{$mail}', expected " . AUTHOR_CONTACT
				. ' — the app store publishes this to everyone who installs the app.';
		}
	}
}

foreach (['bugs', 'repository'] as $element) {
	$node = $root->getElementsByTagName($element)->item(0);
	$url = $node === null ? '' : $node->textContent;
	if (!str_contains($url, PROJECT_HOST)) {
		$findings[] = "{$element}: '{$url}' does not point at " . PROJECT_HOST . '.';
	}
}

foreach (WRITE_SURFACE as $element) {
	if ($root->getElementsByTagName($element)->length > 0) {
		$findings[] = "write surface: <{$element}> is declared, but this app is read-only.";
	}
}

if ($findings !== []) {
	fwrite(STDERR, "info.xml validation failed:\n");
	foreach ($findings as $finding) {
		fwrite(STDERR, "  {$finding}\n");
	}
	exit(1);
}

$compat = $root->getElementsByTagName('nextcloud')->item(0);
$range = $compat instanceof DOMElement
	? $compat->getAttribute('min-version') . '–' . $compat->getAttribute('max-version')
	: 'unknown';
echo 'info.xml: valid, AGPL-3.0-or-later, no write surface, contact '
	. AUTHOR_CONTACT . ", Nextcloud {$range}.\n";
exit(0);
