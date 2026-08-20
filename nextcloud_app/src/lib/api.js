/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import axios from '@nextcloud/axios'
import { generateUrl } from '@nextcloud/router'

/**
 * The app's read-only JSON API.
 *
 * Every endpoint is a GET and none of them takes a user: each request is scoped
 * to whoever is logged in, server-side. `@nextcloud/axios` attaches the request
 * token, which is why these calls work from the page and a bare fetch does not.
 *
 * @param {string} path - endpoint path under `/api/v1/`
 * @param {object} params - query parameters
 * @return {Promise<object>} the decoded payload
 */
async function get(path, params = {}) {
	const { data } = await axios.get(
		generateUrl(`/apps/cairn/api/v1/${path}`),
		{ params },
	)
	return data
}

export const fetchFiles = () => get('files')
export const fetchSteps = (days) => get('steps', { days })
export const fetchHeartRate = (days) => get('heart-rate', { days })
export const fetchWeight = (days) => get('weight', { days })
export const fetchSleep = (nights) => get('sleep', { nights })
export const fetchActivity = (days) => get('activity', { days })
