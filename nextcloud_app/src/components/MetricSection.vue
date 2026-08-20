<!--
  - SPDX-FileCopyrightText: 2026 Max Fiedler
  - SPDX-License-Identifier: AGPL-3.0-or-later
  -->

<template>
	<section class="section">
		<header class="section__head">
			<h3 class="section__title">
				{{ title }}
			</h3>
			<span v-if="subtitle" class="section__subtitle">{{ subtitle }}</span>
		</header>

		<NcLoadingIcon v-if="loading" class="section__loading" :size="32" />

		<p v-else-if="error" class="section__error">
			{{ t('cairn', 'Couldn\'t load this data.') }}
		</p>

		<p v-else-if="empty" class="section__empty">
			<slot name="empty">
				{{ t('cairn', 'Nothing recorded yet.') }}
			</slot>
		</p>

		<slot v-else />
	</section>
</template>

<script setup>
import { translate as t } from '@nextcloud/l10n'
import NcLoadingIcon from '@nextcloud/vue/components/NcLoadingIcon'

/*
 * One section per metric, with the three states every one of them can be in.
 * "Empty" is kept distinct from "failed" on purpose: a folder with no weight in
 * it is a normal state and should not look like a broken page.
 */
defineProps({
	title: { type: String, required: true },
	subtitle: { type: String, default: '' },
	loading: { type: Boolean, default: false },
	error: { type: Boolean, default: false },
	empty: { type: Boolean, default: false },
})
</script>

<style scoped>
.section {
	margin-top: 32px;
}

.section__head {
	display: flex;
	align-items: baseline;
	justify-content: space-between;
	gap: 12px;
	margin-bottom: 12px;
}

.section__title {
	margin: 0;
	font-size: 16px;
	font-weight: 600;
}

.section__subtitle,
.section__empty,
.section__error {
	color: var(--color-text-maxcontrast);
	font-size: 13px;
}

.section__error {
	color: var(--color-error-text, var(--color-error));
}

.section__loading {
	margin: 24px auto;
}
</style>
