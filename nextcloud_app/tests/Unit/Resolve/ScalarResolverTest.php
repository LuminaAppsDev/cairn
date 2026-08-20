<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Resolve;

use OCA\Cairn\Reading\Model\ScalarReading;
use OCA\Cairn\Reading\Resolve\ScalarResolver;
use OCA\Cairn\Tests\Support\Readings;
use PHPUnit\Framework\TestCase;

final class ScalarResolverTest extends TestCase {
	private ScalarResolver $resolver;

	protected function setUp(): void {
		$this->resolver = new ScalarResolver();
	}

	/** @param list<ScalarReading> $readings @return list<float> */
	private function values(array $readings): array {
		$values = array_map(static fn (ScalarReading $r): float => $r->value, $readings);
		sort($values);

		return $values;
	}

	/** A re-typed weight: same source, same instant, the later entry wins. */
	public function testACorrectionSupersedesTheStaleValue(): void {
		$resolved = $this->resolver->resolve([
			Readings::scalar(98.4, '06:21', 'shealth', '06:25'),
			Readings::scalar(88.4, '06:21', 'shealth', '09:02'),
		]);

		self::assertSame([88.4], $this->values($resolved));
	}

	/** Read order must not decide it — the ingest stamp does. */
	public function testTheCorrectionWinsRegardlessOfLineOrder(): void {
		$resolved = $this->resolver->resolve([
			Readings::scalar(88.4, '06:21', 'shealth', '09:02'),
			Readings::scalar(98.4, '06:21', 'shealth', '06:25'),
		]);

		self::assertSame([88.4], $this->values($resolved));
	}

	public function testDifferentSourcesAtOneInstantAreTwoMeasurements(): void {
		$resolved = $this->resolver->resolve([
			Readings::scalar(88.1, '06:40', 'shealth', '07:00'),
			Readings::scalar(88.6, '06:40', 'withings', '07:00'),
		]);

		self::assertSame([88.1, 88.6], $this->values($resolved));
	}

	public function testDifferentInstantsAreAlwaysKept(): void {
		$resolved = $this->resolver->resolve([
			Readings::scalar(88.1, '06:40:00', 'shealth', '07:00'),
			Readings::scalar(88.6, '06:40:01', 'shealth', '07:00'),
		]);

		self::assertSame([88.1, 88.6], $this->values($resolved));
	}

	/**
	 * An undated reading carries no evidence of being newer, so it never
	 * displaces a dated one — whichever order they arrive in.
	 */
	public function testAnUndatedReadingNeverDisplacesADatedOne(): void {
		$dated = Readings::scalar(88.0, '06:50', 'shealth', '07:00');
		$undated = Readings::scalar(999.0, '06:50', 'shealth', null);

		self::assertSame([88.0], $this->values($this->resolver->resolve([$dated, $undated])));
		self::assertSame([88.0], $this->values($this->resolver->resolve([$undated, $dated])));
	}

	/** With nothing to separate them, the first seen in read order stays. */
	public function testAFullTieKeepsTheFirstSeen(): void {
		$resolved = $this->resolver->resolve([
			Readings::scalar(1.0, '06:50', 'shealth', '07:00'),
			Readings::scalar(2.0, '06:50', 'shealth', '07:00'),
		]);

		self::assertSame([1.0], $this->values($resolved));

		$undated = $this->resolver->resolve([
			Readings::scalar(3.0, '06:50', 'shealth', null),
			Readings::scalar(4.0, '06:50', 'shealth', null),
		]);
		self::assertSame([3.0], $this->values($undated));
	}

	/** Provenance is the only identity available, so unattributed ones merge. */
	public function testUnattributedReadingsShareOneBucket(): void {
		$resolved = $this->resolver->resolve([
			Readings::scalar(77.0, '06:50', null, '07:00'),
			Readings::scalar(88.7, '06:50', null, '11:00'),
		]);

		self::assertSame([88.7], $this->values($resolved));
	}

	/**
	 * A source name containing the character a joined key would use as its
	 * separator must not collide with a different source.
	 */
	public function testSourceNamesCannotCollideThroughTheKey(): void {
		$resolved = $this->resolver->resolve([
			Readings::scalar(1.0, '06:50', 'a|1756000000', '07:00'),
			Readings::scalar(2.0, '06:50', 'a', '07:00'),
		]);

		self::assertCount(2, $resolved);
	}

	public function testEmptyInputIsEmptyOutput(): void {
		self::assertSame([], $this->resolver->resolve([]));
	}
}
