<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Controller;

use OCA\Cairn\AppInfo\Application;
use OCA\Cairn\Service\DashboardAssembler;
use OCA\Cairn\Service\OverviewService;
use OCA\Cairn\Service\QueryFactory;
use OCP\AppFramework\Controller;
use OCP\AppFramework\Http;
use OCP\AppFramework\Http\Attribute\NoAdminRequired;
use OCP\AppFramework\Http\JSONResponse;
use OCP\IRequest;
use OCP\IUserSession;

/**
 * Read-only JSON for the dashboard.
 *
 * Every route is a GET, and that is structural rather than incidental: this app
 * consumes the user's files and never changes them (DESIGN.md §7), so a verb
 * that implies mutation appearing in `appinfo/routes.php` means something has
 * gone wrong.
 *
 * There is no user parameter anywhere. Each request is scoped to whoever is
 * logged in, so there is nothing to tamper with — no id to swap for someone
 * else's, and no permission check that could be forgotten.
 *
 * The controller does no work of its own beyond bounding the window, which
 * exists so a crafted `days=100000` cannot make the server walk three centuries
 * of dates.
 */
final class ApiController extends Controller {
	/** Widest window any endpoint will read. A year of daily shards is plenty. */
	private const MAX_DAYS = 365;
	/** Nights are far more expensive per unit than days: each one aggregates
	 *  segments across two shards, so this is deliberately tighter. */
	private const MAX_NIGHTS = 60;

	public function __construct(
		IRequest $request,
		private readonly QueryFactory $queries,
		private readonly DashboardAssembler $assembler,
		private readonly OverviewService $overview,
		private readonly IUserSession $userSession,
	) {
		parent::__construct(Application::APP_ID, $request);
	}

	/**
	 * What is actually on disk: the manifest, and a shard count per metric.
	 *
	 * Not a health metric, and deliberately exposed anyway. The point of this
	 * project is that the files are the system of record and every reader is
	 * replaceable (DESIGN.md §1), which is a claim a self-hoster should be able
	 * to check rather than take on trust.
	 */
	#[NoAdminRequired]
	public function files(): JSONResponse {
		$user = $this->userSession->getUser();
		if ($user === null) {
			throw new \RuntimeException('no user in session');
		}
		$overview = $this->overview->forUser($user->getUID());

		return new JSONResponse([
			'hasRoot' => $overview->hasRoot,
			'formatVersion' => $overview->manifest?->formatVersion,
			'generator' => $overview->manifest?->generator,
			'updatedAt' => $overview->manifest?->updatedDateTime,
			'totalShards' => $overview->totalShards(),
			'metrics' => array_map(
				static fn ($metric): array => [
					'metric' => $metric->metric->value,
					'shards' => $metric->shardCount,
					'firstDay' => $metric->firstDay,
					'lastDay' => $metric->lastDay,
					'unreadableLines' => $metric->newestSkippedLines,
				],
				$overview->metrics,
			),
		]);
	}

	#[NoAdminRequired]
	public function steps(int $days = 14): JSONResponse {
		return $this->respond(
			$days,
			self::MAX_DAYS,
			fn (int $n): array => $this->assembler->steps($this->forCurrentUser(), $n),
		);
	}

	#[NoAdminRequired]
	public function heartRate(int $days = 14): JSONResponse {
		return $this->respond(
			$days,
			self::MAX_DAYS,
			fn (int $n): array => $this->assembler->heartRate($this->forCurrentUser(), $n),
		);
	}

	#[NoAdminRequired]
	public function weight(int $days = 90): JSONResponse {
		return $this->respond(
			$days,
			self::MAX_DAYS,
			fn (int $n): array => $this->assembler->weight($this->forCurrentUser(), $n),
		);
	}

	#[NoAdminRequired]
	public function sleep(int $nights = 7): JSONResponse {
		return $this->respond(
			$nights,
			self::MAX_NIGHTS,
			fn (int $n): array => $this->assembler->sleep($this->forCurrentUser(), $n),
		);
	}

	#[NoAdminRequired]
	public function activity(int $days = 30): JSONResponse {
		return $this->respond(
			$days,
			self::MAX_DAYS,
			fn (int $n): array => $this->assembler->activity($this->forCurrentUser(), $n),
		);
	}

	/**
	 * Validate the window, then hand off.
	 *
	 * Rejected rather than clamped: silently answering a different question than
	 * the one asked is how a frontend bug turns into a puzzling chart instead of
	 * a visible error.
	 *
	 * @param callable(int): array<string, mixed> $build
	 */
	private function respond(int $window, int $max, callable $build): JSONResponse {
		if ($window < 1 || $window > $max) {
			return new JSONResponse(
				['error' => sprintf('window must be between 1 and %d, got %d', $max, $window)],
				Http::STATUS_BAD_REQUEST,
			);
		}

		return new JSONResponse($build($window));
	}

	private function forCurrentUser(): \OCA\Cairn\Reading\HealthQueryService {
		$user = $this->userSession->getUser();
		if ($user === null) {
			// Unreachable in practice: the framework requires a login before any
			// of these routes are dispatched.
			throw new \RuntimeException('no user in session');
		}

		return $this->queries->forUser($user->getUID());
	}
}
