<!--
  - SPDX-FileCopyrightText: 2026 Max Fiedler
  - SPDX-License-Identifier: AGPL-3.0-or-later
  -->

<template>
	<div class="chart">
		<svg
			:viewBox="`0 0 ${width} ${height}`"
			class="chart__svg"
			role="img"
			:aria-label="ariaLabel">
			<g v-for="(bar, index) in bars" :key="bar.day">
				<rect
					:x="bar.x"
					:y="bar.y"
					:width="barWidth"
					:height="bar.height"
					:rx="Math.min(2, barWidth / 3)"
					class="chart__bar"
					:class="[{ 'chart__bar--empty': bar.value === 0 }]" />
				<title>{{ bar.title }}</title>
				<text
					v-if="index % labelEvery === 0"
					:x="bar.x + barWidth / 2"
					:y="height - 4"
					class="chart__label">{{ bar.label }}</text>
			</g>
		</svg>
	</div>
</template>

<script setup>
import { computed } from 'vue'
import { date, number, weekday } from '../lib/format.js'

/*
 * A bar chart in about eighty lines of SVG, rather than a charting library.
 *
 * The whole app renders five charts of two shapes; a library would be a large
 * dependency, a Content-Security-Policy conversation, and a second theming
 * system to reconcile with Nextcloud's. Every colour here comes from a
 * Nextcloud custom property, so the charts follow the user's theme for free.
 */

const props = defineProps({
	/** @type {Array<{day: string, value: number}>} */
	series: { type: Array, required: true },
	unit: { type: String, default: '' },
})

const width = 400
const height = 84
const axis = 16

const max = computed(() => Math.max(1, ...props.series.map((d) => d.value)))
const barWidth = computed(() => props.series.length ? (width / props.series.length) * 0.62 : 0)
// Label every bar when there is room, otherwise thin them out so an axis of
// fourteen days does not turn into a smear.
const labelEvery = computed(() => (props.series.length > 10 ? 3 : 1))

const bars = computed(() => props.series.map((point, index) => {
	const slot = width / props.series.length
	const plot = height - axis
	// A zero day still gets a hairline, so the gap reads as "no data" rather
	// than as the axis itself.
	const barHeight = point.value === 0 ? 1.5 : Math.max(1, (point.value / max.value) * plot)
	return {
		day: point.day,
		value: point.value,
		x: index * slot + (slot - barWidth.value) / 2,
		y: plot - barHeight,
		height: barHeight,
		label: weekday(point.day),
		title: `${date(point.day)}: ${number(point.value)} ${props.unit}`.trim(),
	}
}))

const ariaLabel = computed(() => bars.value.map((b) => b.title).join('; '))
</script>

<style scoped>
.chart__svg {
	display: block;
	width: 100%;
	height: auto;
	overflow: visible;
}

.chart__bar {
	fill: var(--color-primary-element);
}

.chart__bar--empty {
	fill: var(--color-border);
}

.chart__label {
	fill: var(--color-text-maxcontrast);
	font-size: 8px;
	text-anchor: middle;
}
</style>
