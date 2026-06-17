import 'package:cairn/src/profile/bmi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('computes BMI from weight and height', () {
    final bmi = computeBmi(weightKg: 72, heightCm: 178);
    expect(bmi, isNotNull);
    expect(bmi!.value, closeTo(22.7, 0.1));
    expect(bmi.category, BmiCategory.normal);
    expect(bmi.category.isNormal, isTrue);
  });

  test('classifies overweight', () {
    final bmi = computeBmi(weightKg: 86, heightCm: 178);
    expect(bmi!.value, closeTo(27.1, 0.1));
    expect(bmi.category, BmiCategory.overweight);
    expect(bmi.category.isNormal, isFalse);
  });

  group('WHO boundaries (height 100cm → BMI == weight)', () {
    BmiCategory categoryFor(double weight) =>
        computeBmi(weightKg: weight, heightCm: 100)!.category;

    test('18.5 is the bottom of normal', () {
      expect(categoryFor(18.49), BmiCategory.underweight);
      expect(categoryFor(18.5), BmiCategory.normal);
    });

    test('25 is the bottom of overweight', () {
      expect(categoryFor(24.99), BmiCategory.normal);
      expect(categoryFor(25), BmiCategory.overweight);
    });

    test('30 is the bottom of obese', () {
      expect(categoryFor(29.99), BmiCategory.overweight);
      expect(categoryFor(30), BmiCategory.obese);
    });
  });

  test('returns null on missing or non-positive inputs', () {
    expect(computeBmi(heightCm: 178), isNull); // weight missing
    expect(computeBmi(weightKg: 72), isNull); // height missing
    expect(computeBmi(weightKg: 0, heightCm: 178), isNull);
    expect(computeBmi(weightKg: 72, heightCm: 0), isNull);
  });
}
