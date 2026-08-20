/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import { recommended } from '@nextcloud/eslint-config'

/*
 * Nextcloud's own preset. Same reasoning as the Vite config: this code runs
 * inside their frontend, so it follows their conventions rather than a house
 * style that would drift from the components it uses.
 */
export default [
	...recommended,
	{
		ignores: ['js/', 'node_modules/', 'vendor/', 'l10n/'],
	},
]
