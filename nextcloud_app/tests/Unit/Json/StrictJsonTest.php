<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Max Fiedler
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\Cairn\Tests\Unit\Json;

use OCA\Cairn\Reading\Json\StrictJson;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

/**
 * Every case here is one PHP would get wrong by default.
 *
 * These are not defensive tests against hypothetical input: each is a value the
 * mobile reader rejects and PHP's loose typing would accept, which is exactly
 * how two frontends end up disagreeing about one file.
 */
final class StrictJsonTest extends TestCase {
	/** @return array<string, array{mixed}> */
	public static function nonNumbers(): array {
		return [
			'numeric string' => ['62'],
			'float string' => ['62.5'],
			'true' => [true],
			'false' => [false],
			'null' => [null],
			'array' => [[62]],
			'object' => [(object)['value' => 62]],
		];
	}

	#[DataProvider('nonNumbers')]
	public function testNumRejectsAnythingThatIsNotAJsonNumber(mixed $value): void {
		$this->assertNull(StrictJson::num((object)['v' => $value], 'v'));
	}

	public function testNumAcceptsIntsAndFloatsAsFloat(): void {
		$this->assertSame(62.0, StrictJson::num((object)['v' => 62], 'v'));
		$this->assertSame(62.5, StrictJson::num((object)['v' => 62.5], 'v'));
		$this->assertSame(0.0, StrictJson::num((object)['v' => 0], 'v'));
		$this->assertSame(-3.0, StrictJson::num((object)['v' => -3], 'v'));
	}

	public function testStrRejectsNumbersAndBooleans(): void {
		$this->assertNull(StrictJson::str((object)['v' => 62], 'v'));
		$this->assertNull(StrictJson::str((object)['v' => true], 'v'));
		$this->assertSame('62', StrictJson::str((object)['v' => '62'], 'v'));
	}

	/**
	 * A JSON array is not a JSON object. Decoding with `assoc: true` would make
	 * these two indistinguishable, which is why the reader decodes to stdClass.
	 */
	public function testObjRejectsArrays(): void {
		$decodedObject = json_decode('{"body": {"x": 1}}', false);
		$decodedArray = json_decode('{"body": [1, 2]}', false);
		$decodedEmptyArray = json_decode('{"body": []}', false);

		$this->assertNotNull(StrictJson::obj($decodedObject, 'body'));
		$this->assertNull(StrictJson::obj($decodedArray, 'body'));
		$this->assertNull(StrictJson::obj($decodedEmptyArray, 'body'));
	}

	/**
	 * PHP evaluates `"true" == true` as true. The mobile reader compares against
	 * the JSON boolean, so a source emitting the string would flip a night's
	 * "main sleep" flag between the two frontends.
	 */
	public function testIsTrueRequiresTheBooleanNotTheString(): void {
		$this->assertTrue(StrictJson::isTrue((object)['v' => true], 'v'));
		$this->assertFalse(StrictJson::isTrue((object)['v' => 'true'], 'v'));
		$this->assertFalse(StrictJson::isTrue((object)['v' => 1], 'v'));
		$this->assertFalse(StrictJson::isTrue((object)['v' => 'yes'], 'v'));
		$this->assertFalse(StrictJson::isTrue((object)[], 'v'));
	}

	public function testUnitValueNeedsBothHalves(): void {
		$body = json_decode('{"heart_rate": {"value": 62, "unit": "beats/min"}}', false);
		$this->assertSame(['value' => 62.0, 'unit' => 'beats/min'],
			StrictJson::unitValue($body, 'heart_rate'));

		$noUnit = json_decode('{"heart_rate": {"value": 62}}', false);
		$this->assertNull(StrictJson::unitValue($noUnit, 'heart_rate'));

		$noValue = json_decode('{"heart_rate": {"unit": "beats/min"}}', false);
		$this->assertNull(StrictJson::unitValue($noValue, 'heart_rate'));

		$stringValue = json_decode('{"heart_rate": {"value": "62", "unit": "beats/min"}}', false);
		$this->assertNull(StrictJson::unitValue($stringValue, 'heart_rate'));
	}

	public function testMissingKeysAndNullSourcesAreSurvivable(): void {
		$this->assertNull(StrictJson::obj(null, 'anything'));
		$this->assertNull(StrictJson::str(null, 'anything'));
		$this->assertNull(StrictJson::num(null, 'anything'));
		$this->assertNull(StrictJson::unitValue(null, 'anything'));
		$this->assertFalse(StrictJson::isTrue(null, 'anything'));
		$this->assertNull(StrictJson::num((object)[], 'absent'));
	}

	/**
	 * PHP coerces a numeric string array key to an integer. Object property
	 * access does not, which is another reason the reader decodes to stdClass —
	 * a source literally named "7" must stay distinct from one named "07".
	 */
	public function testNumericLookingKeysStayDistinct(): void {
		$decoded = json_decode('{"7": "seven", "07": "oh-seven"}', false);
		$this->assertSame('seven', StrictJson::str($decoded, '7'));
		$this->assertSame('oh-seven', StrictJson::str($decoded, '07'));
	}
}
