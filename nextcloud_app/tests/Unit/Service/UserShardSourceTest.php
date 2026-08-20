<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Service;

use OCA\Cairn\Reading\Model\HealthMetric;
use OCA\Cairn\Reading\ShardSource;
use OCA\Cairn\Service\UserShardSource;
use OCA\Cairn\Tests\Support\BuildsApp;
use PHPUnit\Framework\TestCase;

/**
 * The seam where a user meets the read path.
 *
 * The pure `ShardSource` contract has no notion of users — that is what keeps
 * it runnable against a plain directory and comparable with the phone reader,
 * which only ever has one. This adapter is the single place below the
 * controller where a uid appears.
 */
final class UserShardSourceTest extends TestCase {
	use BuildsApp;

	private function line(string $id): string {
		return '{"header":{"id":"' . $id . '"},"body":{}}';
	}

	public function testSatisfiesThePureContract(): void {
		$source = new UserShardSource($this->shardSourceFor([]), 'admin');

		self::assertInstanceOf(ShardSource::class, $source);
	}

	/**
	 * A list, not a generator: the pure layer resolves a day as a whole — it
	 * compares every line against every other to deduplicate — so laziness buys
	 * nothing, and a plain list is what the contract promises.
	 */
	public function testReturnsAListOfDecodedPoints(): void {
		$source = new UserShardSource($this->shardSourceFor([
			'steps/2026/2026-08-20.jsonl' => $this->line('a') . "\n" . $this->line('b') . "\n",
		]), 'admin');

		$points = $source->readDay(HealthMetric::Steps, '2026-08-20');

		self::assertSame([0, 1], array_keys($points), 'a list, in read order');
		self::assertSame(['a', 'b'], array_map(
			static fn (object $p): string => $p->header->id,
			$points,
		));
	}

	public function testBindsTheUserItWasBuiltFor(): void {
		$storage = $this->shardSourceFor([
			'steps/2026/2026-08-20.jsonl' => $this->line('a') . "\n",
		]);

		self::assertCount(1, (new UserShardSource($storage, 'admin'))
			->readDay(HealthMetric::Steps, '2026-08-20'));
		self::assertCount(0, (new UserShardSource($storage, 'someone-else'))
			->readDay(HealthMetric::Steps, '2026-08-20'));
	}

	public function testAMissingDayIsEmpty(): void {
		$source = new UserShardSource($this->shardSourceFor([]), 'admin');

		self::assertSame([], $source->readDay(HealthMetric::Steps, '2026-08-20'));
	}
}
