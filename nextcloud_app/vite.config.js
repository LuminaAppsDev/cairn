/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import { createAppConfig } from '@nextcloud/vite-config'

/*
 * Nextcloud's own build preset. It emits the ESM bundle the server expects in
 * js/, externalises Vue against what the server already ships, and wires up the
 * app-id prefixes — reproducing that by hand is how a build starts diverging
 * from the platform it has to load inside.
 *
 * js/ is gitignored: the bundle is a build artefact, and the app-store tarball
 * is built with `npm run build` rather than from a committed blob.
 */
export default createAppConfig(
	{
		main: 'src/main.js',
	},
	{
		// The app is served from a folder mounted read-only in the dev
		// container, so nothing may be emitted outside js/.
		emptyOutputDirectory: true,
		// Inline the CSS the components pull in. Nextcloud can serve a separate
		// stylesheet, but a single request keeps the page's first paint simple
		// and avoids a second cache-busted URL to reason about.
		inlineCSS: true,
		config: {
			build: {
				// Matches the browsers Nextcloud 32+ supports; no point shipping
				// transpilation the server itself does not ask for.
				target: 'es2022',
			},
		},
	},
)
