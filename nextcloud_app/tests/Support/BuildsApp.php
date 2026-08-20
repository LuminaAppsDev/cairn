<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Support;

use DateTimeZone;
use OCA\Cairn\Service\CairnRootLocator;
use OCA\Cairn\Service\DisplayTimeZone;
use OCA\Cairn\Service\ManifestReader;
use OCA\Cairn\Service\NextcloudShardSource;
use OCA\Cairn\Service\OverviewService;
use OCA\Cairn\Service\QueryFactory;
use OCP\IDateTimeZone;
use OCP\IUser;
use OCP\IUserSession;

/**
 * Assembles the real server-facing stack on top of stubbed storage.
 *
 * Nothing here is a test double except the two things that genuinely cannot be
 * built without a server — the filesystem and the session. Everything between
 * the controller and the shards is the production wiring, so these tests
 * exercise the same path a request does, including the classes made `final`
 * that a mock could not stand in for.
 */
trait BuildsApp {
	use BuildsStorage;

	protected const ZONE = 'Europe/Berlin';

	/** @param array<string, string> $tree files under `/Cairn` */
	protected function queryFactoryFor(array $tree): QueryFactory {
		return new QueryFactory($this->shardSourceFor($tree), $this->displayTimeZone());
	}

	/** @param array<string, string> $tree */
	protected function overviewServiceFor(array $tree): OverviewService {
		return new OverviewService($this->shardSourceFor($tree), new ManifestReader());
	}

	/** @param array<string, string> $tree */
	protected function shardSourceFor(array $tree): NextcloudShardSource {
		return new NextcloudShardSource(new CairnRootLocator($this->storageWith($tree)));
	}

	/** @param non-empty-string $zone */
	protected function displayTimeZone(string $zone = self::ZONE): DisplayTimeZone {
		$dateTimeZone = $this->createStub(IDateTimeZone::class);
		$dateTimeZone->method('getTimeZone')->willReturn(new DateTimeZone($zone));

		return new DisplayTimeZone($dateTimeZone);
	}

	/** A session with somebody logged in. */
	protected function sessionFor(string $userId = 'admin'): IUserSession {
		$user = $this->createStub(IUser::class);
		$user->method('getUID')->willReturn($userId);

		$session = $this->createStub(IUserSession::class);
		$session->method('getUser')->willReturn($user);

		return $session;
	}

	/** A session with nobody logged in. */
	protected function anonymousSession(): IUserSession {
		$session = $this->createStub(IUserSession::class);
		$session->method('getUser')->willReturn(null);

		return $session;
	}
}
