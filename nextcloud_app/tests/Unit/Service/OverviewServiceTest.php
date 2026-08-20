<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Service;

use OCA\Cairn\Reading\Model\HealthMetric;
use OCA\Cairn\Tests\Support\BuildsApp;
use PHPUnit\Framework\TestCase;

/**
 * Surveying what is on disk.
 *
 * Not a health metric, and exposed anyway: the point of this project is that
 * the files are the system of record and every reader is replaceable, which is
 * a claim a self-hoster should be able to check rather than take on trust.
 */
final class OverviewServiceTest extends TestCase {
	use BuildsApp;

	private function line(): string {
		return '{"header":{"id":"a"},"body":{}}';
	}

	public function testReportsNoRootWhenThereIsNoFolder(): void {
		$service = new \OCA\Cairn\Service\OverviewService(
			new \OCA\Cairn\Service\NextcloudShardSource(
				new \OCA\Cairn\Service\CairnRootLocator($this->storageWithoutCairn()),
			),
			new \OCA\Cairn\Service\ManifestReader(),
		);

		$overview = $service->forUser('admin');

		self::assertFalse($overview->hasRoot);
		self::assertNull($overview->manifest);
		self::assertSame([], $overview->metrics);
		self::assertSame(0, $overview->totalShards());
	}

	/**
	 * Every metric appears, present or not. A dashboard that hid the empty ones
	 * would leave you wondering whether the metric is missing or the row is.
	 */
	public function testEveryMetricIsListedEvenWithNoData(): void {
		$overview = $this->overviewServiceFor([
			'steps/2026/2026-08-20.jsonl' => $this->line() . "\n",
		])->forUser('admin');

		self::assertTrue($overview->hasRoot);
		self::assertCount(count(HealthMetric::all()), $overview->metrics);

		$empty = array_values(array_filter(
			$overview->metrics,
			static fn ($m): bool => $m->metric === HealthMetric::Weight,
		))[0];
		self::assertSame(0, $empty->shardCount);
		self::assertNull($empty->firstDay);
		self::assertNull($empty->lastDay);
	}

	public function testReportsTheRangeAndTheNewestShardsContents(): void {
		$overview = $this->overviewServiceFor([
			'steps/2026/2026-08-18.jsonl' => $this->line() . "\n",
			'steps/2026/2026-08-20.jsonl' => $this->line() . "\n" . $this->line() . "\n",
			'manifest.json' => '{"format_version":1,"generator":"cairn"}',
		])->forUser('admin');

		$steps = array_values(array_filter(
			$overview->metrics,
			static fn ($m): bool => $m->metric === HealthMetric::Steps,
		))[0];

		self::assertSame(2, $steps->shardCount);
		self::assertSame('2026-08-18', $steps->firstDay);
		self::assertSame('2026-08-20', $steps->lastDay);
		self::assertSame(2, $steps->newestDatapoints, 'the newest shard, not the first');
		self::assertSame(0, $steps->newestSkippedLines);
		self::assertSame(2, $overview->totalShards());
		self::assertSame(1, $overview->manifest?->formatVersion);
	}

	/**
	 * Damage is surfaced rather than hidden. A non-zero count here is
	 * informational — usually one torn line from an interrupted sync — and the
	 * day still renders around it.
	 */
	public function testCountsUnreadableLinesInTheNewestShard(): void {
		$overview = $this->overviewServiceFor([
			'steps/2026/2026-08-20.jsonl'
				=> $this->line() . "\n" . '["not","an","object"]' . "\n" . '{"tor',
		])->forUser('admin');

		$steps = array_values(array_filter(
			$overview->metrics,
			static fn ($m): bool => $m->metric === HealthMetric::Steps,
		))[0];

		self::assertSame(1, $steps->newestDatapoints);
		self::assertSame(2, $steps->newestSkippedLines);
	}

	public function testAMissingManifestIsNotFatal(): void {
		$overview = $this->overviewServiceFor([
			'steps/2026/2026-08-20.jsonl' => $this->line() . "\n",
		])->forUser('admin');

		self::assertTrue($overview->hasRoot, 'the folder is readable without one');
		self::assertNull($overview->manifest);
	}
}
