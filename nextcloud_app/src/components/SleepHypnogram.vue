<!--
  - SPDX-FileCopyrightText: 2026 Max Fiedler
  - SPDX-License-Identifier: AGPL-3.0-or-later
  -->

<template>
	<div class="hypnogram">
		<svg
			:viewBox="`0 0 ${width} ${height}`"
			class="hypnogram__svg"
			role="img"
			:aria-label="ariaLabel">
			<rect
				v-for="(segment, index) in segments"
				:key="index"
				:x="segment.x"
				:y="segment.y"
				:width="segment.width"
				:height="rowHeight - 5"
				rx="2"
				class="hypnogram__seg"
				:class="`hypnogram__seg--${segment.stage}`">
				<title>{{ segment.title }}</title>
			</rect>
			<text :x="0" :y="height - 3" class="hypnogram__label hypnogram__label--start">
				{{ startLabel }}
			</text>
			<text :x="width" :y="height - 3" class="hypnogram__label hypnogram__label--end">
				{{ endLabel }}
			</text>
		</svg>
		<ul class="hypnogram__legend">
			<li v-for="row in legend" :key="row.stage">
				<span
					class="hypnogram__swatch"
					:class="`hypnogram__seg--${row.stage}`" />
				{{ row.label }}
			</li>
		</ul>
	</div>
</template>

<script setup>
import { translate as t } from '@nextcloud/l10n'
import { computed } from 'vue'
import { duration, time } from '../lib/format.js'

/*
 * The night as a strip, one row per depth of sleep.
 *
 * The `session` stage is drawn on its own row rather than mixed in with the
 * others: it is a whole-night marker some sources emit *alongside* the real
 * stages, so overlaying it would hide everything underneath.
 */

const props = defineProps({
	night: { type: Object, required: true },
})

const width = 400
const rowHeight = 22
const axis = 14

// Awake at the top, deepest at the bottom — the conventional reading, and the
// reason a hypnogram is legible at a glance.
const ROWS = ['awake', 'in_bed', 'out_of_bed', 'rem', 'light', 'deep', 'asleep_unspecified', 'session']

const STAGE_LABELS = {
	awake: () => t('cairn', 'Awake'),
	in_bed: () => t('cairn', 'In bed'),
	out_of_bed: () => t('cairn', 'Out of bed'),
	rem: () => t('cairn', 'REM'),
	light: () => t('cairn', 'Light'),
	deep: () => t('cairn', 'Deep'),
	asleep_unspecified: () => t('cairn', 'Asleep'),
	session: () => t('cairn', 'Sleep session'),
}

const present = computed(() => {
	const seen = new Set(props.night.segments.map((s) => s.stage))
	return ROWS.filter((stage) => seen.has(stage))
})

const height = computed(() => present.value.length * rowHeight + axis)

const span = computed(() => {
	const start = new Date(props.night.start).getTime()
	const end = new Date(props.night.end).getTime()
	return { start, ms: Math.max(1, end - start) }
})

const segments = computed(() => props.night.segments.map((segment) => {
	const row = present.value.indexOf(segment.stage)
	const from = new Date(segment.start).getTime()
	const to = new Date(segment.end).getTime()
	return {
		stage: segment.stage,
		x: ((from - span.value.start) / span.value.ms) * width,
		// A one-minute segment would otherwise be invisible.
		width: Math.max(1.4, ((to - from) / span.value.ms) * width),
		y: row * rowHeight,
		title: `${STAGE_LABELS[segment.stage]?.() ?? segment.stage} · `
			+ `${time(segment.start)}–${time(segment.end)} · ${duration(segment.durationMs)}`,
	}
}))

const legend = computed(() => present.value.map((stage) => ({
	stage,
	label: STAGE_LABELS[stage]?.() ?? stage,
})))

const startLabel = computed(() => time(props.night.start))
const endLabel = computed(() => time(props.night.end))
const ariaLabel = computed(() => t(
	'cairn',
	'Sleep stages from {start} to {end}',
	{ start: startLabel.value, end: endLabel.value },
))
</script>

<style scoped>
.hypnogram__svg {
	display: block;
	width: 100%;
	height: auto;
	overflow: visible;
}

.hypnogram__label {
	fill: var(--color-text-maxcontrast);
	font-size: 8px;
}

.hypnogram__label--start { text-anchor: start; }
.hypnogram__label--end { text-anchor: end; }

/*
 * Deeper sleep is drawn darker. The scale is built from the theme's primary
 * colour so it tracks a themed instance instead of fighting it.
 */
.hypnogram__seg--awake { --stage-color: var(--color-warning); }
.hypnogram__seg--in_bed,
.hypnogram__seg--out_of_bed { --stage-color: var(--color-border-dark); }
.hypnogram__seg--rem { --stage-color: var(--color-primary-element); }
.hypnogram__seg--light { --stage-color: var(--color-primary-element-light); }
.hypnogram__seg--deep { --stage-color: var(--color-primary-element-hover, var(--color-primary-element)); }
.hypnogram__seg--asleep_unspecified { --stage-color: var(--color-primary-element-light); }
.hypnogram__seg--session { --stage-color: var(--color-border); }

/* One custom property per stage, consumed as a fill in the chart and as a
   background in the legend — so the two can never drift apart. */
rect.hypnogram__seg { fill: var(--stage-color); }
.hypnogram__swatch { background-color: var(--stage-color); }

.hypnogram__legend {
	display: flex;
	flex-wrap: wrap;
	gap: 4px 16px;
	margin-top: 8px;
	padding: 0;
	list-style: none;
	font-size: 12px;
	color: var(--color-text-maxcontrast);
}

.hypnogram__legend li {
	display: flex;
	align-items: center;
	gap: 6px;
}

.hypnogram__swatch {
	display: inline-block;
	width: 10px;
	height: 10px;
	border-radius: 3px;
}
</style>
