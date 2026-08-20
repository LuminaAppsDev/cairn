<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Controller;

use OCA\Cairn\AppInfo\Application;
use OCA\Cairn\Service\HeadlineFiguresService;
use OCA\Cairn\Service\OverviewService;
use OCP\AppFramework\Controller;
use OCP\AppFramework\Http\Attribute\NoAdminRequired;
use OCP\AppFramework\Http\Attribute\NoCSRFRequired;
use OCP\AppFramework\Http\TemplateResponse;
use OCP\IRequest;
use OCP\IUserSession;

/**
 * Renders the single page this app has.
 *
 * Holds no logic beyond resolving who is asking. There is no CSRF token to
 * check because there is nothing to submit, and no admin gate because everyone
 * sees only their own files.
 */
class PageController extends Controller {
	public function __construct(
		IRequest $request,
		private readonly OverviewService $overviewService,
		private readonly HeadlineFiguresService $figuresService,
		private readonly IUserSession $userSession,
	) {
		parent::__construct(Application::APP_ID, $request);
	}

	/**
	 * The Cairn landing page.
	 */
	#[NoAdminRequired]
	#[NoCSRFRequired]
	public function index(): TemplateResponse {
		$user = $this->userSession->getUser();

		$uid = $user?->getUID();

		return new TemplateResponse(
			Application::APP_ID,
			'main',
			[
				'overview' => $uid === null ? null : $this->overviewService->forUser($uid),
				'figures' => $uid === null ? null : $this->figuresService->forUser($uid),
			],
		);
	}
}
