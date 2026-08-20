<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Controller;

use OCA\Cairn\Controller\PageController;
use OCA\Cairn\Service\CairnRootLocator;
use OCA\Cairn\Tests\Support\BuildsApp;
use OCP\AppFramework\Services\IInitialState;
use OCP\IRequest;
use OCP\IUserSession;
use PHPUnit\Framework\TestCase;

/**
 * The page renders nothing itself; it hands the frontend the one fact worth
 * knowing before any request completes.
 */
final class PageControllerTest extends TestCase {
	use BuildsApp;

	/** @var array<string, mixed> */
	private array $state = [];

	/** @param array<string, string> $tree */
	private function controller(array $tree, ?IUserSession $session = null): PageController {
		$this->state = [];
		$initialState = $this->createStub(IInitialState::class);
		$initialState->method('provideInitialState')->willReturnCallback(
			function (string $key, mixed $data): void {
				$this->state[$key] = $data;
			},
		);

		return new PageController(
			$this->createStub(IRequest::class),
			new CairnRootLocator($this->storageWith($tree)),
			$initialState,
			$session ?? $this->sessionFor(),
		);
	}

	public function testRendersTheAppTemplate(): void {
		$response = $this->controller([])->index();

		self::assertSame('main', $response->getTemplateName());
		self::assertSame('cairn', $response->getApp());
	}

	/**
	 * "You have not connected the phone app yet" is worth knowing before five
	 * requests each come back empty — it is the difference between an
	 * explanation and five blank sections.
	 */
	/** The one fact handed over with the page, as the frontend receives it. */
	private function hasRoot(): mixed {
		return $this->state['hasRoot'] ?? null;
	}

	public function testTellsTheFrontendWhetherThereIsAnythingToRead(): void {
		$this->controller(['steps/2026/2026-08-20.jsonl' => ''])->index();
		self::assertTrue($this->hasRoot());

		$this->controller([])->index();
		self::assertTrue($this->hasRoot(), 'an empty Cairn folder still exists');
	}

	public function testAnAnonymousRequestHasNothingToRead(): void {
		$this->controller(
			['steps/2026/2026-08-20.jsonl' => ''],
			$this->anonymousSession(),
		)->index();

		self::assertFalse($this->hasRoot());
	}

	public function testAnotherUserHasNothingToRead(): void {
		$this->controller(
			['steps/2026/2026-08-20.jsonl' => ''],
			$this->sessionFor('someone-else'),
		)->index();

		self::assertFalse($this->hasRoot());
	}
}
