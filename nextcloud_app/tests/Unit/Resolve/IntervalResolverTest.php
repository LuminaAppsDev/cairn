<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Resolve;

use OCA\Cairn\Reading\Model\IntervalReading;
use OCA\Cairn\Reading\Resolve\IntervalResolver;
use OCA\Cairn\Tests\Support\Readings;
use PHPUnit\Framework\TestCase;

final class IntervalResolverTest extends TestCase {
	private IntervalResolver $resolver;

	protected function setUp(): void {
		$this->resolver = new IntervalResolver();
	}

	/** @param list<IntervalReading> $readings */
	private function total(array $readings): float {
		return array_sum(array_map(static fn (IntervalReading $r): float => $r->value, $readings));
	}

	/**
	 * The Samsung Health case: one whole-day record re-read on every sync, its
	 * value climbing. The day's total is the newest snapshot — not their sum,
	 * which would be nonsense, and not the first, which would be stale.
	 */
	public function testCumulativeSnapshotsCollapseToTheNewest(): void {
		$resolved = $this->resolver->resolve([
			Readings::interval(3100.0, '00:00:00', '23:59:59', 'shealth', '09:05'),
			Readings::interval(9040.0, '00:00:00', '23:59:59', 'shealth', '15:05'),
			Readings::interval(14210.0, '00:00:00', '23:59:59', 'shealth', '22:05'),
		]);

		self::assertCount(1, $resolved);
		self::assertSame(14210.0, $this->total($resolved));
	}

	public function testSnapshotOrderOnDiskDoesNotDecideTheTotal(): void {
		$resolved = $this->resolver->resolve([
			Readings::interval(14210.0, '00:00:00', '23:59:59', 'shealth', '22:05'),
			Readings::interval(3100.0, '00:00:00', '23:59:59', 'shealth', '09:05'),
			Readings::interval(9040.0, '00:00:00', '23:59:59', 'shealth', '15:05'),
		]);

		self::assertSame(14210.0, $this->total($resolved));
	}

	/**
	 * The case that separates rank-first from ingest-first: the wearable's name
	 * contains "fit" so it outranks the vendor app, and must win even though the
	 * vendor line was written hours later.
	 */
	public function testSourcePriorityBeatsALaterIngest(): void {
		$resolved = $this->resolver->resolve([
			Readings::interval(2400.0, '12:00', '12:30', 'Galaxy Fit3', '12:40'),
			Readings::interval(1150.0, '12:00', '12:30', 'com.sec.android.app.shealth', '20:10'),
		]);

		self::assertCount(1, $resolved);
		self::assertSame(2400.0, $this->total($resolved));
	}

	public function testAtEqualRankTheLaterIngestWins(): void {
		$resolved = $this->resolver->resolve([
			Readings::interval(310.0, '14:00', '14:10', 'android', '14:30'),
			Readings::interval(845.0, '14:00', '14:10', 'android', '18:30'),
		]);

		self::assertSame(845.0, $this->total($resolved));
	}

	/** Distinct windows are distinct measurements and are summed. */
	public function testDistinctWindowsAreAllKept(): void {
		$resolved = $this->resolver->resolve([
			Readings::interval(1.0, '06:08:10', '06:08:12', 'android', '23:42'),
			Readings::interval(4.0, '06:08:12', '06:08:18', 'android', '23:42'),
			Readings::interval(10.0, '06:28:57', '06:29:03', 'android', '23:42'),
		]);

		self::assertCount(3, $resolved);
		self::assertSame(15.0, $this->total($resolved));
	}

	/**
	 * A real day: one climbing whole-day snapshot from the vendor app plus the
	 * platform's own short deltas. Both survive, because their windows differ.
	 */
	public function testAWholeDayTotalCoexistsWithPerIntervalDeltas(): void {
		$resolved = $this->resolver->resolve([
			Readings::interval(30.0, '00:00:00', '23:59:59', 'shealth', '06:42'),
			Readings::interval(1.0, '06:08:10', '06:08:12', 'android', '06:42'),
			Readings::interval(4.0, '06:08:12', '06:08:18', 'android', '06:42'),
		]);

		self::assertCount(3, $resolved);
		self::assertSame(35.0, $this->total($resolved));
	}

	public function testAnUndatedSnapshotNeverDisplacesADatedOne(): void {
		$dated = Readings::interval(7700.0, '00:00:00', '23:59:59', 'shealth', '21:00');
		$undated = Readings::interval(999999.0, '00:00:00', '23:59:59', 'shealth', null);

		self::assertSame(7700.0, $this->total($this->resolver->resolve([$dated, $undated])));
		self::assertSame(7700.0, $this->total($this->resolver->resolve([$undated, $dated])));
	}

	/** The source is not in the key, so two devices on one window merge. */
	public function testTwoSourcesOnOneWindowCollapseRatherThanDoubleCount(): void {
		$resolved = $this->resolver->resolve([
			Readings::interval(500.0, '10:00', '10:30', 'phone-a', '11:00'),
			Readings::interval(520.0, '10:00', '10:30', 'phone-b', '11:00'),
		]);

		self::assertCount(1, $resolved);
	}

	public function testEmptyInputIsEmptyOutput(): void {
		self::assertSame([], $this->resolver->resolve([]));
	}
}
