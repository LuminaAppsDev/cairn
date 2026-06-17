import 'package:cairn/src/omh/omh_time.dart';
import 'package:flutter/foundation.dart';

/// The current `profile.json` format version. Independent of the cache
/// `manifest.json` version: adding the optional profile file is additive, so
/// the on-disk `format_version` (manifest) is **not** bumped (DESIGN.md §5.4).
const int kProfileFormatVersion = 1;

/// The user's personal profile — height and date of birth — used to compute a
/// dynamic BMI against the latest synced weight.
///
/// Both fields are optional so a partially-filled profile is valid. Stored at
/// `/Cairn/profile.json` and synced; cross-device pull-down lands with the
/// Phase 8 bidirectional sync, so today it pushes up but a second device must
/// re-enter it.
@immutable
class Profile {
  /// Creates a profile.
  const Profile({this.heightCm, this.dateOfBirth});

  /// An empty profile (nothing entered yet).
  factory Profile.empty() => const Profile();

  /// Parses a profile map, tolerating missing/malformed fields.
  factory Profile.fromJson(Map<String, Object?> json) {
    final height = json['height'];
    final heightValue = height is Map<String, Object?> ? height['value'] : null;
    final dob = json['date_of_birth'];
    return Profile(
      heightCm: heightValue is num ? heightValue.toDouble() : null,
      dateOfBirth: dob is String ? DateTime.tryParse(dob) : null,
    );
  }

  /// Body height in centimetres, or `null` if unset.
  final double? heightCm;

  /// Date of birth (a calendar date), or `null` if unset.
  final DateTime? dateOfBirth;

  /// Whether the profile has nothing set.
  bool get isEmpty => heightCm == null && dateOfBirth == null;

  /// Age in whole years at [now], or `null` if no date of birth is set.
  int? ageYears(DateTime now) {
    final dob = dateOfBirth;
    if (dob == null) return null;
    var age = now.year - dob.year;
    final hadBirthday =
        now.month > dob.month || (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthday) age--;
    return age < 0 ? null : age;
  }

  /// Returns a copy with the given fields overridden.
  Profile copyWith({double? heightCm, DateTime? dateOfBirth}) => Profile(
    heightCm: heightCm ?? this.heightCm,
    dateOfBirth: dateOfBirth ?? this.dateOfBirth,
  );

  /// Serialises to the `profile.json` object, stamping `updated_date_time`
  /// with [updatedAt] (local-offset ISO-8601). DoB is a bare calendar date.
  Map<String, Object?> toJson({required DateTime updatedAt}) {
    final dob = dateOfBirth;
    return {
      'format_version': kProfileFormatVersion,
      'generator': 'cairn',
      'updated_date_time': omhDateTime(updatedAt),
      if (heightCm != null) 'height': {'value': heightCm, 'unit': 'cm'},
      if (dob != null)
        'date_of_birth':
            '${dob.year.toString().padLeft(4, '0')}-'
            '${dob.month.toString().padLeft(2, '0')}-'
            '${dob.day.toString().padLeft(2, '0')}',
    };
  }
}
