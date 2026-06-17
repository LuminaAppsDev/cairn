import 'package:flutter/foundation.dart';

/// WHO adult Body Mass Index categories.
enum BmiCategory {
  /// BMI < 18.5.
  underweight,

  /// 18.5 ≤ BMI < 25 — the normal range.
  normal,

  /// 25 ≤ BMI < 30.
  overweight,

  /// BMI ≥ 30.
  obese;

  /// Whether this category is within the normal range.
  bool get isNormal => this == BmiCategory.normal;

  /// A short human-readable label.
  String get label => switch (this) {
    BmiCategory.underweight => 'Underweight',
    BmiCategory.normal => 'Normal',
    BmiCategory.overweight => 'Overweight',
    BmiCategory.obese => 'Obese',
  };
}

/// A computed Body Mass Index and its category.
@immutable
class Bmi {
  /// Creates a BMI from a raw [value].
  Bmi(this.value) : category = categorize(value);

  /// The BMI value (kg/m²).
  final double value;

  /// The WHO adult category for [value].
  final BmiCategory category;

  /// WHO adult BMI bands. Age-independent for adults; age is surfaced
  /// separately for context, not used here.
  static BmiCategory categorize(double bmi) {
    if (bmi < 18.5) return BmiCategory.underweight;
    if (bmi < 25) return BmiCategory.normal;
    if (bmi < 30) return BmiCategory.overweight;
    return BmiCategory.obese;
  }
}

/// Computes BMI = weight(kg) / height(m)², or `null` if either input is
/// missing or non-positive.
Bmi? computeBmi({double? weightKg, double? heightCm}) {
  if (weightKg == null || heightCm == null) return null;
  if (weightKg <= 0 || heightCm <= 0) return null;
  final heightM = heightCm / 100.0;
  return Bmi(weightKg / (heightM * heightM));
}
