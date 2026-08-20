<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit;

use DateTimeImmutable;
use DateTimeZone;
use OCA\Cairn\Reading\Clock;
use OCA\Cairn\Reading\HealthQueryService;
use OCA\Cairn\Tests\Support\DirectoryShardSource;
use OCA\Cairn\Tests\Support\ParityEncoder;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

/**
 * The PHP half of the cross-frontend parity suite.
 *
 * Runs every shared fixture in `test/fixtures/parity/` and checks the answers
 * against the committed goldens. The Dart suite runs the same fixtures. Between
 * them they are the mechanism that keeps two independent implementations of
 * `docs/DESIGN.md` §4.3 honest — see that directory's README for the contract.
 */
final class ParityTest extends TestCase {
	/**
	 * Where the shared fixtures are.
	 *
	 * They live outside this subtree on purpose — they belong to the format,
	 * not to either reader. The dev container mounts them at a fixed path; on a
	 * host run they are found relative to the repository.
	 */
	private static function fixturesDir(): string {
		$fromEnv = getenv('CAIRN_PARITY_FIXTURES');
		$candidates = array_filter([
			$fromEnv === false || $fromEnv === '' ? null : $fromEnv,
			'/parity',
			dirname(__DIR__, 3) . '/test/fixtures/parity',
		]);
		foreach ($candidates as $dir) {
			if (is_dir($dir . '/cases')) {
				return $dir;
			}
		}

		self::fail(
			'No parity fixtures found (looked in: ' . implode(', ', $candidates) . ").\n"
			. 'They live in test/fixtures/parity/ at the repository root; the dev '
			. 'container mounts them at /parity.',
		);
	}

	/** @return array<string, array{string}> */
	public static function cases(): array {
		$dir = self::fixturesDir() . '/cases';
		$found = [];
		$entries = scandir($dir);
		self::assertNotFalse($entries, "cannot list {$dir}");
		foreach ($entries as $entry) {
			if ($entry !== '.' && $entry !== '..' && is_file("{$dir}/{$entry}/spec.json")) {
				$found[$entry] = [$entry];
			}
		}
		ksort($found);

		// Fail closed. A suite that silently finds nothing reports all-clear
		// while proving nothing, which is worse than having no suite.
		if ($found === []) {
			self::fail("No parity cases in {$dir} — the suite would have proved nothing.");
		}

		return $found;
	}

	#[DataProvider('cases')]
	public function testCaseMatchesTheSharedGolden(string $slug): void {
		$dir = self::fixturesDir() . '/cases/' . $slug;
		$spec = $this->readJson("{$dir}/spec.json");
		$expected = $this->readJson("{$dir}/expected.json");

		$display = new DateTimeZone($spec['timezone']);
		$now = new DateTimeImmutable($spec['now'], $display);

		$encoder = new ParityEncoder(
			new HealthQueryService(
				shards: new DirectoryShardSource("{$dir}/tree"),
				clock: new class($now) implements Clock {
					public function __construct(
						private readonly DateTimeImmutable $now,
					) {
					}

					public function now(): DateTimeImmutable {
						return $this->now;
					}
				},
				display: $display,
			),
			$display,
		);

		$actual = [];
		foreach ($spec['queries'] as $query) {
			$actual[$query['id']] = $encoder->run($query);
		}

		self::assertEquals(
			$expected,
			$actual,
			$slug . ': ' . ($spec['description'] ?? '')
			. "\n\nexpected: " . $this->pretty($expected)
			. "\nactual:   " . $this->pretty($actual),
		);
	}

	/**
	 * A readable dump for a failure message, never `false`.
	 *
	 * @param array<string, mixed> $value
	 */
	private function pretty(array $value): string {
		$json = json_encode($value, JSON_PRETTY_PRINT);

		return $json === false ? '<unencodable>' : $json;
	}

	/** @return array<string, mixed> */
	private function readJson(string $path): array {
		$raw = file_get_contents($path);
		self::assertIsString($raw, "unreadable fixture: {$path}");
		$decoded = json_decode($raw, true);
		self::assertIsArray($decoded, "malformed fixture: {$path}");

		return $decoded;
	}
}
