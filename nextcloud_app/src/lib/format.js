/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import { getCanonicalLocale } from '@nextcloud/l10n'

/*
 * Formatting lives here rather than on the server because this is the only
 * layer that knows the viewer's locale. The server sends ISO instants and
 * integer milliseconds — unambiguous, and identical to what the parity fixtures
 * compare — and the browser turns them into something readable.
 */

const locale = () => getCanonicalLocale()

/**
 * @param {number|null} value - a count
 * @return {string} grouped digits, or an em dash
 */
export function number(value) {
	if (value === null || value === undefined) {
		return '—'
	}
	return new Intl.NumberFormat(locale()).format(Math.round(value))
}

/**
 * @param {number|null} value - a measurement
 * @param {number} digits - decimal places
 * @return {string} a formatted decimal, or an em dash
 */
export function decimal(value, digits = 1) {
	if (value === null || value === undefined) {
		return '—'
	}
	return new Intl.NumberFormat(locale(), {
		minimumFractionDigits: digits,
		maximumFractionDigits: digits,
	}).format(value)
}

/**
 * Milliseconds as `7 h 12 min`. Hours and minutes only: sleep and workouts are
 * the only durations here and neither is interesting to the second.
 *
 * @param {number|null} ms - duration in milliseconds
 * @return {string} a readable duration, or an em dash
 */
export function duration(ms) {
	if (ms === null || ms === undefined) {
		return '—'
	}
	const minutes = Math.round(ms / 60000)
	const hours = Math.floor(minutes / 60)
	if (hours === 0) {
		return `${minutes} min`
	}
	return `${hours} h ${String(minutes % 60).padStart(2, '0')} min`
}

/**
 * @param {number|null} fraction - a ratio in 0..1
 * @return {string} a percentage, or an em dash
 */
export function percent(fraction) {
	if (fraction === null || fraction === undefined) {
		return '—'
	}
	return new Intl.NumberFormat(locale(), { style: 'percent' }).format(fraction)
}

/**
 * @param {string} day - an ISO `YYYY-MM-DD` date
 * @param {object} options - Intl.DateTimeFormat options
 * @return {string} the date in the viewer's locale
 */
export function date(day, options = { day: 'numeric', month: 'short' }) {
	return new Intl.DateTimeFormat(locale(), options).format(new Date(`${day}T00:00:00`))
}

/**
 * @param {string} iso - an ISO instant with an offset
 * @return {string} the clock time in the viewer's locale
 */
export function time(iso) {
	return new Intl.DateTimeFormat(locale(), {
		hour: '2-digit',
		minute: '2-digit',
	}).format(new Date(iso))
}

/**
 * A short weekday for a chart axis.
 *
 * @param {string} day - an ISO `YYYY-MM-DD` date
 * @return {string} e.g. `Mon`
 */
export function weekday(day) {
	return new Intl.DateTimeFormat(locale(), { weekday: 'short' })
		.format(new Date(`${day}T00:00:00`))
}

/**
 * Metres as km when far enough to warrant it.
 *
 * @param {number|null} metres - a distance
 * @return {string} a readable distance, or an em dash
 */
export function distance(metres) {
	if (metres === null || metres === undefined) {
		return '—'
	}
	if (metres < 1000) {
		return `${number(metres)} m`
	}
	return `${decimal(metres / 1000, 2)} km`
}
