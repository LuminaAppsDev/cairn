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
			<!-- The day's spread, drawn before the mean so the line sits on top. -->
			<rect
				v-for="point in points"
				:key="`range-${point.day}`"
				:x="point.x - bandWidth / 2"
				:y="point.maxY"
				:width="bandWidth"
				:height="Math.max(2, point.minY - point.maxY)"
				:rx="bandWidth / 2"
				class="chart__band">
				<title>{{ point.title }}</title>
			</rect>
			<polyline
				v-if="points.length > 1"
				:points="meanPath"
				class="chart__line" />
			<circle
				v-for="point in points"
				:key="`mean-${point.day}`"
				:cx="point.x"
				:cy="point.meanY"
				r="2.4"
				class="chart__dot" />
			<text
				v-for="(point, index) in points"
				v-show="index % labelEvery === 0"
				:key="`label-${point.day}`"
				:x="point.x"
				:y="height - 4"
				class="chart__label">{{ point.label }}</text>
		</svg>
	</div>
</template>

<script setup>
import { computed } from 'vue'
import { date, number, weekday } from '../lib/format.js'

/*
 * Daily minimum, mean and maximum. The band matters more than the line here: a
 * resting heart rate and a workout on the same day are not usefully described
 * by one number, and a plain average hides both.
 */

const props = defineProps({
	/** @type {Array<{day: string, min: number, max: number, mean: number, count: number}>} */
	series: { type: Array, required: true },
	unit: { type: String, default: '' },
})

const width = 400
const height = 84
const axis = 16

const bounds = computed(() => {
	if (!props.series.length) {
		return { low: 0, high: 1 }
	}
	const low = Math.min(...props.series.map((d) => d.min))
	const high = Math.max(...props.series.map((d) => d.max))
	// A flat series would divide by zero; give it a nominal span instead.
	return high === low ? { low: low - 1, high: high + 1 } : { low, high }
})

const bandWidth = computed(() => props.series.length ? Math.min(16, (width / props.series.length) * 0.34) : 1)
const labelEvery = computed(() => (props.series.length > 10 ? 3 : 1))

/**
 * Map a measured value onto the chart's vertical axis.
 *
 * @param {number} value - a heart rate from the series
 * @return {number} its y coordinate, in viewBox units
 */
function scale(value) {
	const { low, high } = bounds.value
	const plot = height - axis
	return plot - ((value - low) / (high - low)) * plot
}

const points = computed(() => props.series.map((point, index) => {
	const slot = width / props.series.length
	return {
		day: point.day,
		x: index * slot + slot / 2,
		minY: scale(point.min),
		maxY: scale(point.max),
		meanY: scale(point.mean),
		label: weekday(point.day),
		title: `${date(point.day)}: ${number(point.min)}–${number(point.max)} `
			+ `${props.unit} (⌀ ${number(point.mean)}, ${point.count})`,
	}
}))

const meanPath = computed(() => points.value.map((p) => `${p.x},${p.meanY}`).join(' '))

const ariaLabel = computed(() => points.value.map((p) => p.title).join('; '))
</script>

<style scoped>
.chart__svg {
	display: block;
	width: 100%;
	height: auto;
	overflow: visible;
}

.chart__band {
	fill: var(--color-primary-element-light);
}

.chart__line {
	fill: none;
	stroke: var(--color-primary-element);
	stroke-width: 1.6;
	stroke-linejoin: round;
	stroke-linecap: round;
}

.chart__dot {
	fill: var(--color-primary-element);
}

.chart__label {
	fill: var(--color-text-maxcontrast);
	font-size: 8px;
	text-anchor: middle;
}
</style>
