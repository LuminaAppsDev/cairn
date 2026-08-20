<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Policy;

use OCA\Cairn\Reading\Model\HealthMetric;
use OCA\Cairn\Reading\Policy\SourcePriorityPolicy;
use OCA\Cairn\Tests\Support\Readings;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

final class SourcePriorityPolicyTest extends TestCase {
	private SourcePriorityPolicy $policy;

	protected function setUp(): void {
		$this->policy = new SourcePriorityPolicy();
	}

	/** @return array<string, array{string, int}> */
	public static function wearableNames(): array {
		return [
			'watch' => ['Apple Watch', 0],
			'wear' => ['Wear OS by Google', 1],
			'band' => ['Mi Band 8', 2],
			'fit' => ['Galaxy Fit3', 3],
			'tracker' => ['Some Tracker', 4],
			'no match' => ['com.sec.android.app.shealth', 5],
			'platform' => ['android', 5],
		];
	}

	#[DataProvider('wearableNames')]
	public function testRankIsTheIndexOfTheFirstMatchingFragment(string $name, int $rank): void {
		self::assertSame($rank, $this->policy->rank(HealthMetric::Steps, Readings::source($name)));
	}

	public function testMatchingIsCaseInsensitive(): void {
		self::assertSame(3, $this->policy->rank(HealthMetric::Steps, Readings::source('GALAXY FIT3')));
		self::assertSame(3, $this->policy->rank(HealthMetric::Steps, Readings::source('galaxy fit3')));
	}

	/** The earlier fragment wins when a name contains more than one. */
	public function testTheFirstMatchingFragmentDecides(): void {
		self::assertSame(0, $this->policy->rank(HealthMetric::Steps, Readings::source('Watch Band')));
	}

	public function testAMissingSourceRanksLast(): void {
		self::assertSame(5, $this->policy->rank(HealthMetric::Steps, null));
	}

	/**
	 * Weight has no preferences: you weigh yourself once, so there is no
	 * competing window and a wrist device is not the better scale. Every source
	 * therefore ties, leaving the caller's own tie-break to decide.
	 */
	public function testWeightTreatsEverySourceEqually(): void {
		self::assertSame(0, $this->policy->rank(HealthMetric::Weight, Readings::source('Apple Watch')));
		self::assertSame(0, $this->policy->rank(HealthMetric::Weight, Readings::source('Withings Body+')));
		self::assertSame(0, $this->policy->rank(HealthMetric::Weight, null));
	}

	public function testTheOtherSensedMetricsSharePreferences(): void {
		foreach ([HealthMetric::HeartRate, HealthMetric::Sleep, HealthMetric::Activity] as $metric) {
			self::assertSame(0, $this->policy->rank($metric, Readings::source('Apple Watch')));
			self::assertSame(5, $this->policy->rank($metric, Readings::source('android')));
		}
	}
}
