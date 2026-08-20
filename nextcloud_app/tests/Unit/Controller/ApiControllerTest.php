<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Controller;

use OCA\Cairn\Controller\ApiController;
use OCA\Cairn\Service\DashboardAssembler;
use OCA\Cairn\Tests\Support\BuildsApp;
use OCA\Cairn\Tests\Support\Points;
use OCP\AppFramework\Http;
use OCP\IRequest;
use OCP\IUserSession;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

/**
 * The JSON API, wired to the real read path over stubbed storage.
 *
 * Everything between the controller and the shards is production code, so a
 * request here travels the same path a real one does. What the compatibility
 * matrix proves works, these say *why* — which branch rejected a window, which
 * user's files were read.
 */
final class ApiControllerTest extends TestCase {
	use BuildsApp;

	/** @param array<string, string> $tree */
	private function controller(array $tree = [], ?IUserSession $session = null): ApiController {
		return new ApiController(
			$this->createStub(IRequest::class),
			$this->queryFactoryFor($tree),
			new DashboardAssembler(),
			$this->overviewServiceFor($tree),
			$session ?? $this->sessionFor(),
		);
	}

	/** @return array<string, string> a day of steps and one weight reading */
	private function aDayOfData(): array {
		return [
			'steps/2026/2026-08-20.jsonl'
				=> Points::steps(3100.0, '00:00:00', '23:59:59', '09:05') . "\n"
				. Points::steps(14210.0, '00:00:00', '23:59:59', '22:05') . "\n",
			'weight/2026/2026-08-20.jsonl' => Points::weight(88.4, '06:21', '09:02') . "\n",
		];
	}

	// ----------------------------------------------------- window validation

	/** @return array<string, array{string, int}> */
	public static function outOfRangeWindows(): array {
		return [
			'zero days' => ['steps', 0],
			'negative days' => ['steps', -1],
			'absurd days' => ['steps', 100000],
			'a day past the cap' => ['steps', 366],
			'zero nights' => ['sleep', 0],
			'nights past the cap' => ['sleep', 61],
		];
	}

	/**
	 * Rejected, not clamped. Silently answering a different question than the
	 * one asked turns a frontend bug into a puzzling chart instead of an error.
	 */
	#[DataProvider('outOfRangeWindows')]
	public function testAWindowOutsideTheLimitsIsRejected(string $endpoint, int $window): void {
		$controller = $this->controller();
		$response = $endpoint === 'sleep'
			? $controller->sleep($window)
			: $controller->steps($window);

		self::assertSame(Http::STATUS_BAD_REQUEST, $response->getStatus());
		$data = $response->getData();
		self::assertIsArray($data);
		self::assertArrayHasKey('error', $data);
		self::assertStringContainsString((string)$window, $data['error'],
			'the message should name what was actually asked for');
	}

	public function testTheWindowLimitsThemselvesAreAccepted(): void {
		$controller = $this->controller();

		self::assertSame(Http::STATUS_OK, $controller->steps(1)->getStatus());
		self::assertSame(Http::STATUS_OK, $controller->steps(365)->getStatus());
		self::assertSame(Http::STATUS_OK, $controller->sleep(1)->getStatus());
		self::assertSame(Http::STATUS_OK, $controller->sleep(60)->getStatus());
	}

	/** Nights are far more expensive per unit than days, hence a tighter cap. */
	public function testNightsAreCappedMoreTightlyThanDays(): void {
		$controller = $this->controller();

		self::assertSame(Http::STATUS_OK, $controller->steps(365)->getStatus());
		self::assertSame(Http::STATUS_BAD_REQUEST, $controller->sleep(365)->getStatus());
	}

	// -------------------------------------------------------------- payloads

	public function testStepsResolvesCumulativeSnapshots(): void {
		$response = $this->controller($this->aDayOfData())->steps(7);
		$data = $response->getData();

		self::assertIsArray($data);
		self::assertSame('steps', $data['unit']);
		self::assertCount(7, $data['series'], 'zero-filled, so a chart keeps its slots');
		// The newest snapshot, not the sum of them.
		$total = array_sum(array_column($data['series'], 'value'));
		self::assertSame(14210.0, $total);
	}

	public function testWeightReportsTheLatestReadingAndTheChange(): void {
		$data = $this->controller($this->aDayOfData())->weight(30)->getData();

		self::assertIsArray($data);
		self::assertSame('kg', $data['unit']);
		self::assertNotNull($data['latest']);
		self::assertSame(88.4, $data['latest']['value']);
	}

	/** @return array<string, array{string, string}> */
	public static function endpointsAndTheirKeys(): array {
		return [
			'steps' => ['steps', 'series'],
			'heart rate' => ['heartRate', 'series'],
			'weight' => ['weight', 'series'],
			'sleep' => ['sleep', 'nights'],
			'activity' => ['activity', 'workouts'],
			'files' => ['files', 'metrics'],
		];
	}

	/** An empty folder is a normal state, not an error, on every endpoint. */
	#[DataProvider('endpointsAndTheirKeys')]
	public function testEveryEndpointAnswersOnAnEmptyFolder(string $method, string $key): void {
		$response = $this->controller()->{$method}();

		self::assertSame(Http::STATUS_OK, $response->getStatus());
		$data = $response->getData();
		self::assertIsArray($data);
		self::assertArrayHasKey($key, $data);
	}

	public function testFilesReportsWhatIsOnDisk(): void {
		$data = $this->controller($this->aDayOfData() + [
			'manifest.json' => '{"format_version":1,"generator":"cairn"}',
		])->files()->getData();

		self::assertIsArray($data);
		self::assertTrue($data['hasRoot']);
		self::assertSame(1, $data['formatVersion']);
		self::assertSame('cairn', $data['generator']);
		self::assertSame(2, $data['totalShards']);
		self::assertCount(5, $data['metrics'], 'every metric, present or not');
	}

	// --------------------------------------------------------------- scoping

	/**
	 * Each request reads the session user's files and takes no user parameter,
	 * so there is nothing to swap for somebody else's. The storage stub throws
	 * for any other uid, which is what makes this an assertion rather than a
	 * hope.
	 */
	public function testReadsOnlyTheLoggedInUsersFiles(): void {
		$mine = $this->controller($this->aDayOfData(), $this->sessionFor('admin'))
			->steps(7)->getData();
		self::assertIsArray($mine);
		self::assertSame(14210.0, $mine['today']);

		// The same storage, a different session. The stub holds files for
		// 'admin' alone, so anyone else reads an empty folder — not an error,
		// because a folder you cannot see is indistinguishable from one that is
		// not there, and either way there is nothing to show.
		$theirs = $this->controller($this->aDayOfData(), $this->sessionFor('someone-else'))
			->steps(7)->getData();
		self::assertIsArray($theirs);
		self::assertNull($theirs['today'], 'another user must not see these steps');
		self::assertSame(0.0, array_sum(array_column($theirs['series'], 'value')));
	}

	public function testAnAnonymousRequestIsRefused(): void {
		$controller = $this->controller([], $this->anonymousSession());

		$this->expectException(\RuntimeException::class);
		$controller->steps(7);
	}
}
