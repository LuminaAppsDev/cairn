<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Controller;

use OCA\Cairn\AppInfo\Application;
use OCA\Cairn\Service\CairnRootLocator;
use OCP\AppFramework\Controller;
use OCP\AppFramework\Http\Attribute\NoAdminRequired;
use OCP\AppFramework\Http\Attribute\NoCSRFRequired;
use OCP\AppFramework\Http\TemplateResponse;
use OCP\AppFramework\Services\IInitialState;
use OCP\IRequest;
use OCP\IUserSession;

/**
 * Renders the single page this app has.
 *
 * Holds no logic beyond resolving who is asking. There is no CSRF token to
 * check because there is nothing to submit, and no admin gate because everyone
 * sees only their own files.
 */
final class PageController extends Controller {
	public function __construct(
		IRequest $request,
		private readonly CairnRootLocator $locator,
		private readonly IInitialState $initialState,
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
		$uid = $this->userSession->getUser()?->getUID();

		// Handed over with the page rather than fetched. Whether there is a
		// /Cairn folder at all is the one thing worth knowing before any request
		// completes: it is the difference between an explanation of how to
		// connect the phone app and five sections that each load and come back
		// empty.
		$this->initialState->provideInitialState(
			'hasRoot',
			$uid !== null && $this->locator->locate($uid) !== null,
		);

		return new TemplateResponse(Application::APP_ID, 'main');
	}
}
