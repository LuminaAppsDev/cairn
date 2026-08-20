<!--
  - SPDX-FileCopyrightText: 2026 Max Fiedler
  - SPDX-License-Identifier: AGPL-3.0-or-later
  -->

<template>
	<div class="tile">
		<span class="tile__label">{{ label }}</span>
		<strong class="tile__value">{{ value }}<small v-if="unit" class="tile__unit">{{ unit }}</small></strong>
		<span v-if="caption" class="tile__caption">{{ caption }}</span>
	</div>
</template>

<script setup>
defineProps({
	label: { type: String, required: true },
	value: { type: [String, Number], required: true },
	unit: { type: String, default: '' },
	caption: { type: String, default: '' },
})
</script>

<style scoped>
.tile {
	display: flex;
	flex-direction: column;
	gap: 2px;
	padding: 14px 16px;
	border: 1px solid var(--color-border);
	border-radius: var(--border-radius-large, 12px);
	background-color: var(--color-background-hover);
}

.tile__label {
	font-size: 11px;
	text-transform: uppercase;
	letter-spacing: 0.04em;
	color: var(--color-text-maxcontrast);
}

.tile__value {
	font-size: 22px;
	font-variant-numeric: tabular-nums;
}

.tile__unit {
	margin-inline-start: 4px;
	font-size: 13px;
	font-weight: normal;
	color: var(--color-text-maxcontrast);
}

.tile__caption {
	font-size: 12px;
	color: var(--color-text-maxcontrast);
}
</style>
