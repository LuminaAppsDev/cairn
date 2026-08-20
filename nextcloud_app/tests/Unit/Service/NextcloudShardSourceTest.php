<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Service;

use OCA\Cairn\Reading\Model\HealthMetric;
use OCA\Cairn\Service\CairnRootLocator;
use OCA\Cairn\Service\NextcloudShardSource;
use OCA\Cairn\Tests\Support\BuildsStorage;
use OCP\Files\IRootFolder;
use PHPUnit\Framework\TestCase;

/**
 * The app's only contact with Nextcloud's filesystem.
 *
 * Covered end-to-end by the compatibility matrix and the packaged-app check,
 * which prove the whole thing works — but not *which* branch handled a missing
 * folder, a torn line or an over-long one. That is what these are for.
 */
final class NextcloudShardSourceTest extends TestCase {
	use BuildsStorage;

	private function sourceFor(IRootFolder $root): NextcloudShardSource {
		return new NextcloudShardSource(new CairnRootLocator($root));
	}

	private function line(string $id): string {
		return '{"header":{"id":"' . $id . '"},"body":{}}';
	}

	// ------------------------------------------------------------ discovery

	public function testFindsShardsAcrossYearFolders(): void {
		$source = $this->sourceFor($this->storageWith([
			'steps/2026/2026-08-20.jsonl' => '',
			'steps/2026/2026-08-19.jsonl' => '',
			'steps/2025/2025-12-31.jsonl' => '',
		]));

		self::assertSame(
			['2025-12-31', '2026-08-19', '2026-08-20'],
			$source->listShardDays('admin', HealthMetric::Steps),
			'ascending, because read order is part of the semantics',
		);
	}

	/** A folder that is not there is an empty result, never an error. */
	public function testMissingFolderIsEmptyNotAnError(): void {
		$source = $this->sourceFor($this->storageWith(['steps/2026/2026-08-20.jsonl' => '']));

		self::assertSame([], $source->listShardDays('admin', HealthMetric::Weight));
		self::assertSame([], iterator_to_array(
			$source->readShard('admin', HealthMetric::Weight, '2026-08-20'),
			false,
		));
	}

	public function testNoCairnFolderIsEmptyNotAnError(): void {
		$source = $this->sourceFor($this->storageWithoutCairn());

		self::assertFalse($source->hasRoot('admin'));
		self::assertSame([], $source->listShardDays('admin', HealthMetric::Steps));
	}

	/** Somebody could have a *file* called Cairn. That is not a folder. */
	public function testCairnAsAFileIsNotAFolder(): void {
		$source = $this->sourceFor($this->storageWithCairnAsAFile());

		self::assertFalse($source->hasRoot('admin'));
	}

	/** Only `YYYY-MM-DD.jsonl` is a shard; the folder may hold anything else. */
	public function testIgnoresFilesThatAreNotShards(): void {
		$source = $this->sourceFor($this->storageWith([
			'steps/2026/2026-08-20.jsonl' => '',
			'steps/2026/notes.txt' => '',
			'steps/2026/2026-08-20.jsonl.bak' => '',
			'steps/2026/.jsonl' => '',
			'steps/2026/20260820.jsonl' => '',
			'steps/loose.jsonl' => '',
		]));

		self::assertSame(['2026-08-20'], $source->listShardDays('admin', HealthMetric::Steps));
	}

	// -------------------------------------------------------------- reading

	public function testReadsEveryUsableLineInOrder(): void {
		$source = $this->sourceFor($this->storageWith([
			'steps/2026/2026-08-20.jsonl'
				=> $this->line('a') . "\n" . $this->line('b') . "\n" . $this->line('c') . "\n",
		]));

		$points = iterator_to_array($source->readShard('admin', HealthMetric::Steps, '2026-08-20'), false);

		self::assertCount(3, $points);
		self::assertSame(['a', 'b', 'c'], array_map(
			static fn (object $p): string => $p->header->id,
			$points,
		));
	}

	/**
	 * A damaged shard degrades to fewer readings, never to an error. The torn
	 * line is last, which is the only place a real one can be.
	 */
	public function testSkipsUnusableLinesAndCountsThem(): void {
		$source = $this->sourceFor($this->storageWith([
			'steps/2026/2026-08-20.jsonl' => implode("\n", [
				$this->line('a'),
				'["not","an","object"]',
				'',
				'   ',
				'42',
				$this->line('b'),
				'{"header":{"id":"tor',
			]),
		]));

		$reader = $source->readShard('admin', HealthMetric::Steps, '2026-08-20');
		$points = iterator_to_array($reader, false);

		self::assertCount(2, $points);
		// Blank lines are separators, not damage, so they are not counted.
		self::assertSame(3, $reader->getReturn(), 'array, bare number, torn line');
	}

	/** Blank lines alone are not damage. */
	public function testBlankLinesAreNotCountedAsDamage(): void {
		$source = $this->sourceFor($this->storageWith([
			'steps/2026/2026-08-20.jsonl' => "\n\n" . $this->line('a') . "\n\n\n",
		]));

		$reader = $source->readShard('admin', HealthMetric::Steps, '2026-08-20');
		self::assertCount(1, iterator_to_array($reader, false));
		self::assertSame(0, $reader->getReturn());
	}

	/**
	 * The generator returns a skipped count, and `getReturn()` throws unless the
	 * generator finished — including on the paths that never yield at all.
	 */
	public function testTheSkippedCountIsAvailableOnEveryPath(): void {
		$source = $this->sourceFor($this->storageWith(['steps/2026/2026-08-20.jsonl' => '']));

		foreach (['2026-08-20', '2026-01-01', 'not-a-date'] as $day) {
			$reader = $source->readShard('admin', HealthMetric::Steps, $day);
			iterator_to_array($reader, false);
			self::assertSame(0, $reader->getReturn(), "day {$day}");
		}
	}

	/**
	 * A line longer than the cap is discarded whole, counted once, and does not
	 * disturb the lines around it — the reason the cap exists is that an
	 * unbounded read would buffer it all into memory.
	 */
	public function testAnOverlongLineIsSkippedOnceAndNeighboursSurvive(): void {
		$huge = '{"header":{"id":"' . str_repeat('x', 200000) . '"}}';
		$source = $this->sourceFor($this->storageWith([
			'steps/2026/2026-08-20.jsonl'
				=> $this->line('a') . "\n" . $huge . "\n" . $this->line('b') . "\n",
		]));

		$reader = $source->readShard('admin', HealthMetric::Steps, '2026-08-20');
		$points = iterator_to_array($reader, false);

		self::assertSame(['a', 'b'], array_map(
			static fn (object $p): string => $p->header->id,
			$points,
		));
		self::assertSame(1, $reader->getReturn(), 'one line, not one per chunk');
	}

	/**
	 * Validated by the method itself, not by its caller. Today `$day` only ever
	 * arrives from a pattern-matched listing, but a "show me this day" feature
	 * would hand it request data, and a `../` would walk out of the folder.
	 */
	public function testRefusesADayThatIsNotADate(): void {
		$source = $this->sourceFor($this->storageWith([
			'steps/2026/2026-08-20.jsonl' => $this->line('a') . "\n",
		]));

		foreach (['../../etc/passwd', '2026-08-20/../..', '', 'yesterday', "2026-08-20\n"] as $day) {
			self::assertSame([], iterator_to_array(
				$source->readShard('admin', HealthMetric::Steps, $day),
				false,
			), "day {$day}");
		}
	}

	// ---------------------------------------------------------- root files

	public function testReadsAJsonFileFromTheRoot(): void {
		$source = $this->sourceFor($this->storageWith([
			'manifest.json' => '{"format_version":1,"generator":"cairn"}',
		]));

		$manifest = $source->readRootJson('admin', 'manifest.json');
		self::assertNotNull($manifest);
		self::assertSame(1, $manifest->format_version);
	}

	public function testRootJsonIsNullWhenAbsentOrUnusable(): void {
		$source = $this->sourceFor($this->storageWith([
			'manifest.json' => 'not json at all',
			'profile.json' => '[1,2,3]',
		]));

		self::assertNull($source->readRootJson('admin', 'manifest.json'), 'invalid JSON');
		self::assertNull($source->readRootJson('admin', 'profile.json'), 'JSON, but not an object');
		self::assertNull($source->readRootJson('admin', 'absent.json'));
	}
}
