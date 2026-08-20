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
			<polyline v-if="points.length > 1" :points="path" class="chart__line" />
			<circle
				v-for="point in points"
				:key="point.at"
				:cx="point.x"
				:cy="point.y"
				r="2"
				class="chart__dot">
				<title>{{ point.title }}</title>
			</circle>
			<text
				v-if="points.length"
				:x="0"
				:y="height - 4"
				class="chart__label chart__label--start">{{ points[0].label }}</text>
			<text
				v-if="points.length > 1"
				:x="width"
				:y="height - 4"
				class="chart__label chart__label--end">{{ points[points.length - 1].label }}</text>
		</svg>
	</div>
</template>

<script setup>
import { computed } from 'vue'
import { date, decimal } from '../lib/format.js'

/*
 * A trend line for readings that arrive irregularly — weight, typically once a
 * morning and not every morning. Points are spaced evenly by index rather than
 * by time: the shape of the trend is what matters, and a true time axis would
 * leave large gaps that say nothing.
 */

const props = defineProps({
	/** @type {Array<{at: string, day: string, value: number}>} */
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
	const values = props.series.map((d) => d.value)
	const low = Math.min(...values)
	const high = Math.max(...values)
	// Weight moves in kilograms across a range of tens, so a plain min/max
	// scale would turn ordinary noise into a mountain range. Pad it.
	const pad = Math.max(0.5, (high - low) * 0.25)
	return { low: low - pad, high: high + pad }
})

const points = computed(() => props.series.map((point, index) => {
	const step = props.series.length > 1 ? width / (props.series.length - 1) : 0
	const { low, high } = bounds.value
	const plot = height - axis
	return {
		at: point.at,
		x: index * step,
		y: plot - ((point.value - low) / (high - low)) * plot,
		label: date(point.day),
		title: `${date(point.day)}: ${decimal(point.value)} ${props.unit}`.trim(),
	}
}))

const path = computed(() => points.value.map((p) => `${p.x},${p.y}`).join(' '))
const ariaLabel = computed(() => points.value.map((p) => p.title).join('; '))
</script>

<style scoped>
.chart__svg {
	display: block;
	width: 100%;
	height: auto;
	overflow: visible;
}

.chart__line {
	fill: none;
	stroke: var(--color-primary-element);
	stroke-width: 1.8;
	stroke-linejoin: round;
	stroke-linecap: round;
}

.chart__dot {
	fill: var(--color-primary-element);
}

.chart__label {
	fill: var(--color-text-maxcontrast);
	font-size: 8px;
}

.chart__label--start {
	text-anchor: start;
}

.chart__label--end {
	text-anchor: end;
}
</style>
