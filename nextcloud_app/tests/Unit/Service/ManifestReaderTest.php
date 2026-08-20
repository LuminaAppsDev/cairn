<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Service;

use OCA\Cairn\Service\ManifestReader;
use PHPUnit\Framework\TestCase;

/**
 * The manifest is metadata, never authority — the shards are the data. So every
 * field is optional or defaulted, and nothing here throws: a reader that
 * refused to work without a valid manifest would break on a folder that is
 * otherwise perfectly readable.
 */
final class ManifestReaderTest extends TestCase {
	private ManifestReader $reader;

	protected function setUp(): void {
		$this->reader = new ManifestReader();
	}

	private function parse(string $json): ?object {
		return $this->reader->parse(json_decode($json, false));
	}

	public function testReadsAWellFormedManifest(): void {
		$manifest = $this->parse('{"format_version":1,"generator":"cairn",'
			. '"updated_date_time":"2026-08-20T06:46:00+02:00",'
			. '"sync_anchors":{"steps":"2026-08-20T06:46:00+02:00"},'
			. '"devices":["Galaxy Fit3"]}');

		self::assertNotNull($manifest);
		self::assertSame(1, $manifest->formatVersion);
		self::assertSame('cairn', $manifest->generator);
		self::assertSame('2026-08-20T06:46:00+02:00', $manifest->updatedDateTime);
		self::assertSame(['steps' => '2026-08-20T06:46:00+02:00'], $manifest->syncAnchors);
		self::assertSame(['Galaxy Fit3'], $manifest->devices);
	}

	public function testNothingToParseIsNull(): void {
		self::assertNull($this->reader->parse(null));
	}

	/** An empty manifest is still a manifest. */
	public function testAnEmptyManifestFallsBackRatherThanFailing(): void {
		$manifest = $this->parse('{}');

		self::assertNotNull($manifest);
		self::assertSame(ManifestReader::DEFAULT_FORMAT_VERSION, $manifest->formatVersion);
		self::assertNull($manifest->generator);
		self::assertNull($manifest->updatedDateTime);
		self::assertSame([], $manifest->syncAnchors);
		self::assertSame([], $manifest->devices);
	}

	/**
	 * Strict typing, as everywhere on the read path: a value of the wrong JSON
	 * type is absent, not coerced. `"1"` is not a format version.
	 */
	public function testWronglyTypedFieldsAreTreatedAsAbsent(): void {
		$manifest = $this->parse('{"format_version":"1","generator":7,'
			. '"updated_date_time":false,"sync_anchors":[],"devices":"none"}');

		self::assertNotNull($manifest);
		self::assertSame(ManifestReader::DEFAULT_FORMAT_VERSION, $manifest->formatVersion);
		self::assertNull($manifest->generator);
		self::assertNull($manifest->updatedDateTime);
		self::assertSame([], $manifest->syncAnchors);
		self::assertSame([], $manifest->devices);
	}

	/**
	 * A newer phone may record anchors for metrics this build has never heard
	 * of. Skipping them is what lets an older web app read a newer folder
	 * without complaint.
	 */
	public function testAnchorsForUnknownMetricsAreSkipped(): void {
		$manifest = $this->parse('{"sync_anchors":{"steps":"2026-08-20T06:46:00+02:00",'
			. '"blood-pressure":"2026-08-20T06:46:00+02:00","weight":42}}');

		self::assertNotNull($manifest);
		self::assertSame(['steps' => '2026-08-20T06:46:00+02:00'], $manifest->syncAnchors,
			'unknown metric dropped, and a non-string anchor with it');
	}

	public function testNonStringDevicesAreDropped(): void {
		$manifest = $this->parse('{"devices":["Galaxy Fit3",7,null,{"a":1},"Pixel"]}');

		self::assertNotNull($manifest);
		self::assertSame(['Galaxy Fit3', 'Pixel'], $manifest->devices);
	}
}
