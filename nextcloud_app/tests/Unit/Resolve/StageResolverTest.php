<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Resolve;

use OCA\Cairn\Reading\Model\SleepStage;
use OCA\Cairn\Reading\Resolve\StageResolver;
use OCA\Cairn\Tests\Support\Readings;
use PHPUnit\Framework\TestCase;

final class StageResolverTest extends TestCase {
	private StageResolver $resolver;

	protected function setUp(): void {
		$this->resolver = new StageResolver();
	}

	/**
	 * The rule most likely to be ported wrong. Two sources describe the same
	 * minutes and disagree about what they were; one window is one span of time,
	 * so exactly one segment survives and the wearable decides the stage.
	 *
	 * A port that keys on the stage as well keeps both, and then reports an
	 * awakening the phone never counted.
	 */
	public function testOneWindowSurvivesEvenWhenTheStagesDisagree(): void {
		$resolved = $this->resolver->resolve([
			Readings::stage(SleepStage::Deep, '02:00', '02:40', 'Galaxy Fit3'),
			Readings::stage(SleepStage::Awake, '02:00', '02:40', 'com.sec.android.app.shealth'),
		]);

		self::assertCount(1, $resolved);
		self::assertSame(SleepStage::Deep, $resolved[0]->stage);
	}

	public function testTheWearableWinsRegardlessOfOrder(): void {
		$resolved = $this->resolver->resolve([
			Readings::stage(SleepStage::Awake, '02:00', '02:40', 'com.sec.android.app.shealth'),
			Readings::stage(SleepStage::Deep, '02:00', '02:40', 'Galaxy Fit3'),
		]);

		self::assertCount(1, $resolved);
		self::assertSame(SleepStage::Deep, $resolved[0]->stage);
	}

	/** At equal rank, a sensed segment beats a hand-entered one. */
	public function testAutomaticBeatsSelfReportedAtEqualRank(): void {
		$resolved = $this->resolver->resolve([
			Readings::stage(SleepStage::Awake, '01:00', '04:00', 'shealth', 'self-reported'),
			Readings::stage(SleepStage::Deep, '01:00', '04:00', 'shealth', 'sensed'),
		]);

		self::assertCount(1, $resolved);
		self::assertSame(SleepStage::Deep, $resolved[0]->stage);
	}

	/**
	 * Replayed segments after a crash carry fresh identifiers but identical
	 * content, so deduplication has to be idempotent on exact repeats.
	 */
	public function testExactDuplicatesCollapse(): void {
		$segment = Readings::stage(SleepStage::Light, '01:00', '01:30', 'shealth');
		$resolved = $this->resolver->resolve([$segment, $segment, $segment]);

		self::assertCount(1, $resolved);
	}

	public function testAdjacentWindowsAreDistinctSegments(): void {
		$resolved = $this->resolver->resolve([
			Readings::stage(SleepStage::Light, '01:00', '01:30', 'shealth'),
			Readings::stage(SleepStage::Deep, '01:30', '02:00', 'shealth'),
		]);

		self::assertCount(2, $resolved);
	}

	public function testAFullTieKeepsTheFirstSeen(): void {
		$resolved = $this->resolver->resolve([
			Readings::stage(SleepStage::Rem, '03:00', '03:30', 'shealth'),
			Readings::stage(SleepStage::Deep, '03:00', '03:30', 'shealth'),
		]);

		self::assertCount(1, $resolved);
		self::assertSame(SleepStage::Rem, $resolved[0]->stage);
	}

	public function testEmptyInputIsEmptyOutput(): void {
		self::assertSame([], $this->resolver->resolve([]));
	}
}
