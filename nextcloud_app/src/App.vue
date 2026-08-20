<!--
  - SPDX-FileCopyrightText: 2026 Max Fiedler
  - SPDX-License-Identifier: AGPL-3.0-or-later
  -->

<template>
	<NcContent appName="cairn">
		<NcAppContent>
			<div class="cairn">
				<header class="cairn__head">
					<h2>{{ t('cairn', 'Cairn') }}</h2>
					<p class="cairn__subtitle">
						{{ t('cairn', 'A read-only view of the health files in your own storage.') }}
					</p>
				</header>

				<NcEmptyContent
					v-if="!hasRoot"
					:name="t('cairn', 'No Cairn folder yet')"
					:description="t('cairn', 'The Cairn phone app writes your health data to a folder called Cairn at the top level of your files. Connect the app to this Nextcloud and run a sync.')">
					<template #icon>
						<FolderIcon />
					</template>
				</NcEmptyContent>

				<template v-else>
					<!-- Today, at a glance. -->
					<div class="cairn__tiles">
						<StatTile
							:label="t('cairn', 'Steps today')"
							:value="steps.data ? number(steps.data.today) : '—'"
							:caption="stepsCaption" />
						<StatTile
							:label="t('cairn', 'Last night')"
							:value="lastNight ? duration(lastNight.totalSleepMs) : '—'"
							:caption="sleepCaption" />
						<StatTile
							:label="t('cairn', 'Latest weight')"
							:value="latestWeight ? decimal(latestWeight.value) : '—'"
							:unit="latestWeight ? weight.data.unit : ''"
							:caption="weightCaption" />
						<StatTile
							:label="t('cairn', 'Heart rate')"
							:value="heartRate.data && heartRate.data.mean !== null
								? number(heartRate.data.mean)
								: '—'"
							:unit="heartRate.data && heartRate.data.mean !== null ? 'bpm' : ''"
							:caption="heartCaption" />
						<StatTile
							:label="t('cairn', 'Workouts')"
							:value="activity.data ? number(activity.data.count) : '—'"
							:caption="activityCaption" />
					</div>

					<MetricSection
						:title="t('cairn', 'Steps')"
						:subtitle="n('cairn', 'Last %n day', 'Last %n days', DAYS)"
						:loading="steps.loading"
						:error="steps.error"
						:empty="!!steps.data && steps.data.daysReported === 0">
						<BarChart
							v-if="steps.data"
							:series="steps.data.series"
							:unit="t('cairn', 'steps')" />
					</MetricSection>

					<MetricSection
						:title="t('cairn', 'Heart rate')"
						:subtitle="n('cairn', 'Last %n day', 'Last %n days', DAYS)"
						:loading="heartRate.loading"
						:error="heartRate.error"
						:empty="!!heartRate.data && heartRate.data.series.length === 0">
						<RangeChart
							v-if="heartRate.data"
							:series="heartRate.data.series"
							unit="bpm" />
						<p class="cairn__note">
							{{ t('cairn', 'The band is each day\'s range; the line is its average.') }}
						</p>
					</MetricSection>

					<MetricSection
						:title="t('cairn', 'Sleep')"
						:loading="sleep.loading"
						:error="sleep.error"
						:empty="!!sleep.data && sleep.data.nights.length === 0">
						<template #empty>
							{{ t('cairn', 'No sleep tracked recently.') }}
						</template>
						<template v-if="selectedNight">
							<!--
								Nights come back newest first, so "earlier" moves
								forward through the list. Both buttons carry a word
								as well as an arrow: an arrow alone is ambiguous
								when the list runs backwards from the way a
								calendar reads.
							-->
							<div class="cairn__nights">
								<NcButton
									:disabled="nightIndex >= lastNightIndex"
									:aria-label="t('cairn', 'Earlier night')"
									@click="nightIndex += 1">
									<template #icon>
										<ChevronLeftIcon :size="20" />
									</template>
									{{ t('cairn', 'Earlier') }}
								</NcButton>
								<span class="cairn__night-label">
									<strong>{{ nightHeading }}</strong>
									<span class="cairn__night-range">{{ nightRange }}</span>
								</span>
								<NcButton
									:disabled="nightIndex === 0"
									:aria-label="t('cairn', 'Later night')"
									@click="nightIndex -= 1">
									<template #icon>
										<ChevronRightIcon :size="20" />
									</template>
									{{ t('cairn', 'Later') }}
								</NcButton>
							</div>
							<div class="cairn__tiles cairn__tiles--compact">
								<StatTile
									:label="t('cairn', 'Time asleep')"
									:value="duration(selectedNight.totalSleepMs)"
									:caption="selectedNight.timeInBedMs
										? t('cairn', '{total} in bed', { total: duration(selectedNight.timeInBedMs) })
										: ''" />
								<StatTile
									:label="t('cairn', 'Awakenings')"
									:value="number(selectedNight.awakenings)" />
								<StatTile
									:label="t('cairn', 'Efficiency')"
									:value="percent(selectedNight.efficiency)"
									:caption="selectedNight.efficiency === null
										? t('cairn', 'No wake markers recorded')
										: ''" />
							</div>
							<SleepHypnogram v-if="selectedNight.segments.length" :night="selectedNight" />
							<p v-if="selectedNight.sources.length > 1" class="cairn__note">
								{{ t('cairn', 'Multiple sources tracked this night; totals may overlap.') }}
							</p>
						</template>
					</MetricSection>

					<MetricSection
						:title="t('cairn', 'Weight')"
						:subtitle="weightChangeLabel"
						:loading="weight.loading"
						:error="weight.error"
						:empty="!!weight.data && weight.data.series.length === 0">
						<template #empty>
							{{ t('cairn', 'No weight data yet.') }}
						</template>
						<LineChart
							v-if="weight.data && weight.data.series.length"
							:series="weight.data.series"
							:unit="weight.data.unit" />
					</MetricSection>

					<MetricSection
						:title="t('cairn', 'Activity')"
						:subtitle="n('cairn', 'Last %n day', 'Last %n days', WORKOUT_DAYS)"
						:loading="activity.loading"
						:error="activity.error"
						:empty="!!activity.data && activity.data.count === 0">
						<template #empty>
							{{ t('cairn', 'No workouts recorded recently.') }}
						</template>
						<ul v-if="activity.data" class="cairn__workouts">
							<li v-for="(workout, index) in activity.data.workouts" :key="index">
								<span class="cairn__workout-name">{{ activityName(workout.activity) }}</span>
								<span class="cairn__workout-when">
									{{ date(workout.start.slice(0, 10)) }} · {{ time(workout.start) }}
								</span>
								<span class="cairn__workout-stats">
									{{ duration(workout.durationMs) }}
									<template v-if="workout.distanceM"> · {{ distance(workout.distanceM) }}</template>
									<template v-if="workout.kcal"> · {{ number(workout.kcal) }} kcal</template>
								</span>
							</li>
						</ul>
					</MetricSection>

					<MetricSection
						:title="t('cairn', 'Files on disk')"
						:subtitle="files.data ? n('cairn', '%n shard file', '%n shard files', files.data.totalShards) : ''"
						:loading="files.loading"
						:error="files.error">
						<p class="cairn__note cairn__note--lead">
							{{ t('cairn', 'These files are the record. Everything above is read from them, and Cairn never changes them — delete this app and you lose nothing.') }}
						</p>
						<div v-if="files.data" class="cairn__table-wrap">
							<table class="cairn__files">
								<thead>
									<tr>
										<th>{{ t('cairn', 'Metric') }}</th>
										<th class="numeric">
											{{ t('cairn', 'Shards') }}
										</th>
										<th>{{ t('cairn', 'From') }}</th>
										<th>{{ t('cairn', 'To') }}</th>
										<th class="numeric">
											{{ t('cairn', 'Unreadable lines') }}
										</th>
									</tr>
								</thead>
								<tbody>
									<tr v-for="row in files.data.metrics" :key="row.metric">
										<td><code>{{ row.metric }}</code></td>
										<td class="numeric">
											{{ number(row.shards) }}
										</td>
										<td>{{ row.firstDay ? date(row.firstDay) : '—' }}</td>
										<td>{{ row.lastDay ? date(row.lastDay) : '—' }}</td>
										<td class="numeric" :class="{ warn: row.unreadableLines > 0 }">
											{{ row.unreadableLines > 0 ? number(row.unreadableLines) : '—' }}
										</td>
									</tr>
								</tbody>
							</table>
						</div>
						<p v-if="files.data" class="cairn__note">
							{{ t('cairn', 'Format version {version}, written by {generator}.',
								{ version: files.data.formatVersion, generator: files.data.generator }) }}
						</p>
					</MetricSection>
				</template>
			</div>
		</NcAppContent>
	</NcContent>
</template>

<script setup>
import { loadState } from '@nextcloud/initial-state'
import { translatePlural as n, translate as t } from '@nextcloud/l10n'
import { computed, onMounted, reactive, ref, watch } from 'vue'
import NcAppContent from '@nextcloud/vue/components/NcAppContent'
import NcButton from '@nextcloud/vue/components/NcButton'
import NcContent from '@nextcloud/vue/components/NcContent'
import NcEmptyContent from '@nextcloud/vue/components/NcEmptyContent'
import ChevronLeftIcon from 'vue-material-design-icons/ChevronLeft.vue'
import ChevronRightIcon from 'vue-material-design-icons/ChevronRight.vue'
import FolderIcon from 'vue-material-design-icons/Folder.vue'
import BarChart from './components/BarChart.vue'
import LineChart from './components/LineChart.vue'
import MetricSection from './components/MetricSection.vue'
import RangeChart from './components/RangeChart.vue'
import SleepHypnogram from './components/SleepHypnogram.vue'
import StatTile from './components/StatTile.vue'
import { fetchActivity, fetchFiles, fetchHeartRate, fetchSleep, fetchSteps, fetchWeight } from './lib/api.js'
import { date, decimal, distance, duration, number, percent, time } from './lib/format.js'

const DAYS = 14
const WEIGHT_DAYS = 90
const NIGHTS = 7
const WORKOUT_DAYS = 30

// Whether there is anything to read at all is decided server-side and handed
// over with the page, so the empty state paints immediately instead of after
// five requests have come back empty.
const hasRoot = loadState('cairn', 'hasRoot', false)

/**
 * A tiny request wrapper: one reactive record per section, so each can show its
 * own loading and error state. One metric failing must not blank the others.
 *
 * @param {() => Promise<object>} loader - returns a promise for the payload
 * @return {object} reactive `{ loading, error, data }`
 */
function resource(loader) {
	const state = reactive({ loading: true, error: false, data: null })
	state.load = async () => {
		state.loading = true
		state.error = false
		try {
			state.data = await loader()
		} catch {
			state.error = true
		} finally {
			state.loading = false
		}
	}
	return state
}

const steps = resource(() => fetchSteps(DAYS))
const heartRate = resource(() => fetchHeartRate(DAYS))
const weight = resource(() => fetchWeight(WEIGHT_DAYS))
const sleep = resource(() => fetchSleep(NIGHTS))
const activity = resource(() => fetchActivity(WORKOUT_DAYS))
const files = resource(() => fetchFiles())

onMounted(() => {
	if (!hasRoot) {
		return
	}
	// Fired together rather than in sequence: they are independent reads and
	// the slowest one should not wait behind the others.
	steps.load()
	heartRate.load()
	weight.load()
	sleep.load()
	activity.load()
	files.load()
})

// Which night is on screen: 0 is the most recent, counting backwards.
const nightIndex = ref(0)
const nights = computed(() => sleep.data?.nights ?? [])
const lastNightIndex = computed(() => Math.max(0, nights.value.length - 1))
const selectedNight = computed(() => nights.value[nightIndex.value] ?? null)
const lastNight = computed(() => nights.value[0] ?? null)

// A reload can return fewer nights than before, which would otherwise leave the
// index pointing past the end and the section apparently empty.
watch(nights, (list) => {
	if (nightIndex.value > list.length - 1) {
		nightIndex.value = 0
	}
})

const nightHeading = computed(() => {
	if (!selectedNight.value) {
		return ''
	}
	if (nightIndex.value === 0) {
		return t('cairn', 'Last night')
	}
	return date(selectedNight.value.night, { weekday: 'long', day: 'numeric', month: 'long' })
})

/*
 * The onset and final waking, which is what tells two nights apart when both
 * are filed under the same date — a sleep beginning before midnight is filed
 * under the day it started, so an evening onset and the following night's early
 * one share a date.
 */
const nightRange = computed(() => {
	if (!selectedNight.value) {
		return ''
	}
	const night = selectedNight.value
	const day = nightIndex.value === 0
		? date(night.night, { weekday: 'long', day: 'numeric', month: 'long' })
		: ''
	const span = `${time(night.start)} – ${time(night.end)}`
	return day ? `${day} · ${span}` : span
})
const latestWeight = computed(() => weight.data?.latest ?? null)

const stepsCaption = computed(() => {
	if (!steps.data) {
		return ''
	}
	if (steps.data.today === null) {
		return t('cairn', 'no sync yet today')
	}
	if (steps.data.average === null) {
		return ''
	}
	return t('cairn', '{average} a day on average', { average: number(steps.data.average) })
})

const sleepCaption = computed(() => lastNight.value ? date(lastNight.value.night) : '')

const weightCaption = computed(() => latestWeight.value ? date(latestWeight.value.at.slice(0, 10)) : '')

const heartCaption = computed(() => {
	const data = heartRate.data
	if (!data || data.min === null) {
		return ''
	}
	return t(
		'cairn',
		'{min}–{max} over {days} days',
		{ min: number(data.min), max: number(data.max), days: DAYS },
	)
})

const activityCaption = computed(() => {
	if (!activity.data || activity.data.count === 0) {
		return ''
	}
	return duration(activity.data.totalDurationMs)
})

const weightChangeLabel = computed(() => {
	const change = weight.data?.change
	if (change === null || change === undefined) {
		return ''
	}
	const sign = change > 0 ? '+' : ''
	return t(
		'cairn',
		'{change} {unit} over this period',
		{ change: `${sign}${decimal(change)}`, unit: weight.data.unit },
	)
})

/**
 * Health stores report activity names as shouty constants (`WALKING`). Title
 * case reads better and does not pretend to be a translation of a value we do
 * not control.
 *
 * @param {string} raw - the source's activity name
 * @return {string} a readable name
 */
function activityName(raw) {
	return raw.replace(/_/g, ' ').toLowerCase()
		.replace(/(^|\s)\S/g, (c) => c.toUpperCase())
}
</script>

<style scoped>
.cairn {
	box-sizing: border-box;
	width: 100%;
	max-width: 1040px;
	margin: 0 auto;
	padding: 24px 32px 48px;
	color: var(--color-main-text);
}

.cairn__head h2 {
	margin: 0 0 4px;
	font-size: 20px;
	font-weight: 600;
}

.cairn__subtitle {
	margin: 0 0 24px;
	color: var(--color-text-maxcontrast);
}

.cairn__tiles {
	display: grid;
	grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
	gap: 12px;
}

.cairn__tiles--compact {
	grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
	margin-bottom: 16px;
}

.cairn__note {
	margin: 8px 0 0;
	color: var(--color-text-maxcontrast);
	font-size: 13px;
}

.cairn__workouts {
	margin: 0;
	padding: 0;
	list-style: none;
}

.cairn__workouts li {
	display: grid;
	grid-template-columns: 1fr auto;
	gap: 2px 16px;
	padding: 10px 0;
	border-bottom: 1px solid var(--color-border);
}

.cairn__workouts li:last-child {
	border-bottom: none;
}

.cairn__workout-name {
	font-weight: 600;
}

.cairn__workout-when,
.cairn__workout-stats {
	color: var(--color-text-maxcontrast);
	font-size: 13px;
}

.cairn__workout-stats {
	grid-column: 2;
	grid-row: 1 / span 2;
	align-self: center;
	text-align: end;
	font-variant-numeric: tabular-nums;
}

.cairn__nights {
	display: flex;
	align-items: center;
	justify-content: space-between;
	gap: 12px;
	margin-bottom: 16px;
}

.cairn__night-label {
	display: flex;
	flex-direction: column;
	align-items: center;
	gap: 2px;
	text-align: center;
}

.cairn__night-range {
	color: var(--color-text-maxcontrast);
	font-size: 13px;
	font-variant-numeric: tabular-nums;
}

.cairn__note--lead {
	margin-bottom: 12px;
}

/* Wide tables scroll inside their own box; the page never scrolls sideways. */
.cairn__table-wrap {
	overflow-x: auto;
}

.cairn__files {
	width: 100%;
	border-collapse: collapse;
}

.cairn__files th,
.cairn__files td {
	padding: 8px 12px;
	text-align: start;
	white-space: nowrap;
	border-bottom: 1px solid var(--color-border);
}

.cairn__files tbody tr:last-child td {
	border-bottom: none;
}

.cairn__files th {
	font-size: 11px;
	font-weight: 600;
	text-transform: uppercase;
	letter-spacing: 0.04em;
	color: var(--color-text-maxcontrast);
}

.cairn__files .numeric {
	text-align: end;
	font-variant-numeric: tabular-nums;
}

.cairn__files .warn {
	color: var(--color-warning-text, var(--color-warning));
	font-weight: 600;
}
</style>
