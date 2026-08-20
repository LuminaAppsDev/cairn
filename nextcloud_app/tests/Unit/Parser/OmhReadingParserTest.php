<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Parser;

use DateTimeZone;
use OCA\Cairn\Reading\Model\SleepStage;
use OCA\Cairn\Reading\Parser\OmhReadingParser;
use PHPUnit\Framework\TestCase;

/**
 * Parsing rules, checked against datapoints shaped exactly like the ones in a
 * real export (`com.sec.android.app.shealth`, whole-second timestamps with a
 * local offset).
 */
final class OmhReadingParserTest extends TestCase {
	private OmhReadingParser $parser;

	protected function setUp(): void {
		$this->parser = new OmhReadingParser(new DateTimeZone('Europe/Berlin'));
	}

	private function point(string $json): object {
		$decoded = json_decode($json, false);
		self::assertIsObject($decoded);

		return $decoded;
	}

	private function heartRate(string $extraHeader = '', string $body = ''): object {
		$body = $body !== '' ? $body : '"heart_rate":{"value":84.0,"unit":"beats/min"},'
			. '"effective_time_frame":{"date_time":"2026-08-20T00:00:02+02:00"}';

		return $this->point('{"header":{"id":"9c9d8932-0adc-49fe-bbc7-b28d4209e877",'
			. '"creation_date_time":"2026-08-20T06:42:17+02:00",'
			. '"schema_id":{"namespace":"omh","name":"heart-rate","version":"1.0"}'
			. $extraHeader . '},"body":{' . $body . '}}');
	}

	public function testParsesAHeartRateReading(): void {
		$reading = $this->parser->parseScalar($this->heartRate(
			',"acquisition_provenance":{"source_name":"com.sec.android.app.shealth",'
			. '"modality":"sensed","source_creation_date_time":"2026-08-20T00:00:02+02:00"}',
		));

		self::assertNotNull($reading);
		self::assertSame(84.0, $reading->value);
		self::assertSame('beats/min', $reading->unit);
		self::assertSame('2026-08-20 00:00:02', $reading->at->format('Y-m-d H:i:s'));
		self::assertSame('com.sec.android.app.shealth', $reading->source?->name);
		self::assertFalse($reading->source->isManual());
		self::assertSame('2026-08-20 06:42:17', $reading->ingestedAt?->format('Y-m-d H:i:s'));
	}

	/**
	 * The rule a faithful-looking port gets wrong: provenance is all-or-nothing,
	 * so a name without a modality yields no source at all.
	 */
	public function testProvenanceNeedsBothNameAndModality(): void {
		$nameOnly = $this->heartRate(
			',"acquisition_provenance":{"source_name":"com.sec.android.app.shealth"}',
		);
		self::assertNull($this->parser->provenance($nameOnly));

		$modalityOnly = $this->heartRate(',"acquisition_provenance":{"modality":"sensed"}');
		self::assertNull($this->parser->provenance($modalityOnly));

		$noBlock = $this->heartRate();
		self::assertNull($this->parser->provenance($noBlock));

		$both = $this->heartRate(
			',"acquisition_provenance":{"source_name":"x","modality":"sensed"}',
		);
		self::assertNotNull($this->parser->provenance($both));
	}

	public function testAReadingWithoutAnIngestTimeStillParses(): void {
		$point = $this->point('{"header":{"schema_id":{"namespace":"omh","name":"heart-rate",'
			. '"version":"1.0"}},"body":{"heart_rate":{"value":70.0,"unit":"beats/min"},'
			. '"effective_time_frame":{"date_time":"2026-08-20T10:00:00+02:00"}}}');

		$reading = $this->parser->parseScalar($point);
		self::assertNotNull($reading);
		self::assertNull($reading->ingestedAt);
	}

	public function testAUnitlessMeasureDropsTheWholeReading(): void {
		$point = $this->heartRate(body: '"heart_rate":{"value":84.0},'
			. '"effective_time_frame":{"date_time":"2026-08-20T00:00:02+02:00"}');
		self::assertNull($this->parser->parseScalar($point));
	}

	public function testAStringValueDropsTheWholeReading(): void {
		$point = $this->heartRate(body: '"heart_rate":{"value":"84","unit":"beats/min"},'
			. '"effective_time_frame":{"date_time":"2026-08-20T00:00:02+02:00"}');
		self::assertNull($this->parser->parseScalar($point));
	}

	public function testAnUnparseableTimestampDropsTheWholeReading(): void {
		$point = $this->heartRate(body: '"heart_rate":{"value":84.0,"unit":"beats/min"},'
			. '"effective_time_frame":{"date_time":"not-a-timestamp"}');
		self::assertNull($this->parser->parseScalar($point));
	}

	public function testWeightUsesTheSameScalarPath(): void {
		$point = $this->point('{"header":{"creation_date_time":"2026-08-20T06:42:18+02:00",'
			. '"schema_id":{"namespace":"omh","name":"body-weight","version":"2.0"}},'
			. '"body":{"body_weight":{"value":88.0999984741211,"unit":"kg"},'
			. '"effective_time_frame":{"date_time":"2026-08-20T06:19:41+02:00"}}}');

		$reading = $this->parser->parseScalar($point);
		self::assertNotNull($reading);
		self::assertEqualsWithDelta(88.0999984741211, $reading->value, 1e-9);
		self::assertSame('kg', $reading->unit);
	}

	public function testParsesAWholeDayStepSnapshot(): void {
		$point = $this->point('{"header":{"creation_date_time":"2026-08-20T06:42:17+02:00",'
			. '"schema_id":{"namespace":"omh","name":"step-count","version":"3.0"}},'
			. '"body":{"step_count":{"value":30.0,"unit":"steps"},'
			. '"effective_time_frame":{"time_interval":{'
			. '"start_date_time":"2026-08-20T00:00:00+02:00",'
			. '"end_date_time":"2026-08-20T23:59:59+02:00"}}}}');

		$reading = $this->parser->parseInterval($point);
		self::assertNotNull($reading);
		self::assertSame(30.0, $reading->value);
		self::assertSame('2026-08-20 00:00:00', $reading->start->format('Y-m-d H:i:s'));
		self::assertSame('2026-08-20 23:59:59', $reading->end->format('Y-m-d H:i:s'));
	}

	/** The body's own `duration` is ignored; duration comes from the window. */
	public function testWorkoutDurationIsRecomputedNotTrusted(): void {
		$point = $this->point('{"header":{"creation_date_time":"2026-08-20T06:42:17+02:00",'
			. '"schema_id":{"namespace":"omh","name":"physical-activity","version":"1.0"}},'
			. '"body":{"activity_name":"WALKING",'
			. '"effective_time_frame":{"time_interval":{'
			. '"start_date_time":"2026-08-19T17:01:45+02:00",'
			. '"end_date_time":"2026-08-19T17:12:56+02:00"}},'
			. '"duration":{"value":999.0,"unit":"min"},'
			. '"distance":{"value":666.0,"unit":"m"},'
			. '"kcal_burned":{"value":59.0,"unit":"kcal"},'
			. '"base_movement_quantity":{"value":616.4,"unit":"steps"}}}');

		$workout = $this->parser->parseWorkout($point);
		self::assertNotNull($workout);
		self::assertSame('WALKING', $workout->activityName);
		self::assertSame(671000, $workout->durationMillis());
		self::assertSame(666.0, $workout->distanceMeters);
		self::assertSame(59.0, $workout->kcal);
		// Rounded half away from zero, not truncated.
		self::assertSame(616, $workout->steps);
	}

	public function testParsesEveryKnownSleepStage(): void {
		foreach (SleepStage::cases() as $stage) {
			$reading = $this->parser->parseSleepStage($this->sleepStage($stage->value));
			self::assertNotNull($reading, "stage {$stage->value} should parse");
			self::assertSame($stage, $reading->stage);
		}
	}

	public function testAnUnknownSleepStageDropsTheReading(): void {
		self::assertNull($this->parser->parseSleepStage($this->sleepStage('dozing')));
	}

	private function sleepStage(string $wire): object {
		return $this->point('{"header":{"creation_date_time":"2026-08-20T06:42:17+02:00",'
			. '"schema_id":{"namespace":"cairn","name":"sleep-stage","version":"1.0"}},'
			. '"body":{"sleep_stage":"' . $wire . '",'
			. '"effective_time_frame":{"time_interval":{'
			. '"start_date_time":"2026-08-20T00:08:54+02:00",'
			. '"end_date_time":"2026-08-20T00:09:54+02:00"}}}}');
	}

	/** Only `schema_id.name` discriminates; namespace and version are ignored. */
	public function testSchemaNameIsReadAndNamespaceVersionAreNot(): void {
		$odd = $this->point('{"header":{"schema_id":{"namespace":"omh","name":"sleep-stage",'
			. '"version":"9.9"}},"body":{"sleep_stage":"deep",'
			. '"effective_time_frame":{"time_interval":{'
			. '"start_date_time":"2026-08-20T01:00:00+02:00",'
			. '"end_date_time":"2026-08-20T02:00:00+02:00"}}}}');

		self::assertSame('sleep-stage', $this->parser->schemaName($odd));
		self::assertNotNull($this->parser->parseSleepStage($odd));
	}

	public function testSleepEpisodeRequiresTotalSleepTime(): void {
		$withTotal = $this->episode('"total_sleep_time":{"value":330.0,"unit":"min"},'
			. '"is_main_sleep":true,"number_of_awakenings":3,'
			. '"light_sleep_duration":{"value":180.0,"unit":"min"}');
		$episode = $this->parser->parseSleepEpisode($withTotal);
		self::assertNotNull($episode);
		self::assertSame(330 * 60000, $episode->totalSleepMillis);
		self::assertTrue($episode->isMainSleep);
		self::assertSame(3, $episode->awakenings);
		self::assertSame(180 * 60000, $episode->lightMillis);
		self::assertNull($episode->deepMillis);

		self::assertNull($this->parser->parseSleepEpisode(
			$this->episode('"is_main_sleep":true'),
		));
	}

	/** `"true"` is not `true` — PHP's loose comparison would say otherwise. */
	public function testIsMainSleepRejectsTheStringTrue(): void {
		$episode = $this->parser->parseSleepEpisode($this->episode(
			'"total_sleep_time":{"value":330.0,"unit":"min"},"is_main_sleep":"true"',
		));
		self::assertNotNull($episode);
		self::assertFalse($episode->isMainSleep);
	}

	public function testAwakeningsDefaultToZeroWhenAbsentOrWrongType(): void {
		$absent = $this->parser->parseSleepEpisode($this->episode(
			'"total_sleep_time":{"value":330.0,"unit":"min"}',
		));
		self::assertNotNull($absent);
		self::assertSame(0, $absent->awakenings);

		$stringy = $this->parser->parseSleepEpisode($this->episode(
			'"total_sleep_time":{"value":330.0,"unit":"min"},"number_of_awakenings":"3"',
		));
		self::assertNotNull($stringy);
		self::assertSame(0, $stringy->awakenings);
	}

	private function episode(string $body): object {
		return $this->point('{"header":{"creation_date_time":"2026-08-20T06:42:17+02:00",'
			. '"schema_id":{"namespace":"omh","name":"sleep-episode","version":"1.0"}},'
			. '"body":{"effective_time_frame":{"time_interval":{'
			. '"start_date_time":"2026-08-20T00:08:54+02:00",'
			. '"end_date_time":"2026-08-20T06:30:00+02:00"}},' . $body . '}}');
	}
}
