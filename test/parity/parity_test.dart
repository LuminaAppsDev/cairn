// SPDX-FileCopyrightText: 2026 Max Fiedler
// SPDX-License-Identifier: MIT

@Tags(['parity'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/query/health_query_service.dart';
import 'package:cairn/src/query/night_sleep.dart';
import 'package:cairn/src/storage/jsonl_omh_file_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The Flutter half of the cross-frontend parity suite.
///
/// `docs/DESIGN.md` §4.3 makes the read semantics a property of the file format:
/// this app and the Nextcloud web app must give the same answers for the same
/// bytes, or the files stop being one source of truth. Both suites run the
/// fixtures in `test/fixtures/parity/`; see that directory's README for the
/// contract and the shared result encoding.
void main() {
  final fixtures = Directory(p.join('test', 'fixtures', 'parity', 'cases'));

  test('the parity fixtures are present', () {
    // Fail closed: a suite that silently finds nothing reports all-clear while
    // proving nothing, which is worse than not having one.
    expect(
      fixtures.existsSync(),
      isTrue,
      reason: 'missing ${fixtures.path} — the parity suite would prove nothing',
    );
    expect(
      _caseDirs(fixtures),
      isNotEmpty,
      reason: 'no cases under ${fixtures.path}',
    );
  });

  test('the process timezone matches the fixtures', () {
    // Dart takes its zone from the environment rather than as a parameter, so
    // the wrong TZ silently changes which day a reading belongs to. Assert the
    // actual offsets rather than the zone name: that also catches the two hosts
    // carrying different tzdata, which no name comparison would.
    final winter = DateTime(2026).timeZoneOffset;
    final summer = DateTime(2026, 7).timeZoneOffset;
    expect(
      [winter, summer],
      [const Duration(hours: 1), const Duration(hours: 2)],
      reason:
          'The parity fixtures are authored in Europe/Berlin (+01:00 winter, '
          '+02:00 summer) but this process is in a different zone.\n'
          'Run: TZ=Europe/Berlin flutter test',
    );
  });

  for (final caseDir in _caseDirs(fixtures)) {
    final slug = p.basename(caseDir.path);
    final spec =
        jsonDecode(File(p.join(caseDir.path, 'spec.json')).readAsStringSync())
            as Map<String, Object?>;
    final expected =
        jsonDecode(
              File(p.join(caseDir.path, 'expected.json')).readAsStringSync(),
            )
            as Map<String, Object?>;

    test('$slug matches the shared golden', () async {
      final now = DateTime.parse(spec['now']! as String);
      final service = OmhHealthQueryService(
        store: JsonlOmhFileStore(
          root: Directory(p.join(caseDir.path, 'tree')),
        ),
        clock: () => now,
      );

      final actual = <String, Object?>{};
      for (final query
          in (spec['queries']! as List<Object?>).cast<Map<String, Object?>>()) {
        actual[query['id']! as String] = await _run(service, query);
      }

      expect(
        actual,
        expected,
        reason: '$slug: ${spec['description'] ?? ''}',
      );
    });
  }
}

List<Directory> _caseDirs(Directory fixtures) {
  if (!fixtures.existsSync()) return const [];
  final dirs =
      fixtures
          .listSync()
          .whereType<Directory>()
          .where((d) => File(p.join(d.path, 'spec.json')).existsSync())
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return dirs;
}

/// Runs one query and encodes it in the shared wire form.
///
/// An unimplemented name throws rather than being skipped, so adding a query to
/// a fixture forces the other frontend to implement it too.
Future<Object?> _run(
  HealthQueryService service,
  Map<String, Object?> query,
) async {
  final name = query['name']! as String;
  switch (name) {
    case 'todayStepTotal':
      return service.todayStepTotal();
    case 'dailySteps':
      final series = await service.dailySteps(days: query['days']! as int);
      return [
        for (final d in series) {'day': _date(d.day), 'value': d.value},
      ];
    case 'dailyHeartRate':
      final stats = await service.dailyHeartRate(days: query['days']! as int);
      return [
        for (final s in stats)
          {
            'day': _date(s.day),
            'min': s.min,
            'max': s.max,
            'mean': s.mean,
            'count': s.count,
          },
      ];
    case 'latestScalar':
      final reading = await service.latestScalar(_metric(query));
      if (reading == null) return null;
      return {
        'value': reading.value,
        'unit': reading.unit,
        'at': _instant(reading.at),
        'source': reading.source?.name,
      };
    case 'scalarSeries':
      final series = await service.scalarSeries(
        _metric(query),
        days: query['days']! as int,
      );
      return [
        for (final r in series) {'value': r.value, 'at': _instant(r.at)},
      ];
    case 'recentWorkouts':
      final workouts = await service.recentWorkouts(
        days: query['days']! as int,
      );
      return [
        for (final w in workouts)
          {
            'activity': w.activityName,
            'start': _instant(w.start),
            'end': _instant(w.end),
            'durationMs': w.duration.inMilliseconds,
          },
      ];
    case 'lastNNights':
      final nights = await service.lastNNights(query['n']! as int);
      return [for (final n in nights) _night(n)];
    default:
      throw StateError(
        "parity query '$name' is not implemented by the "
        'Dart reader',
      );
  }
}

Map<String, Object?> _night(NightSleep night) => {
  'night': _date(night.night),
  'start': _instant(night.start),
  'end': _instant(night.end),
  'totalSleepMs': night.totalSleep.inMilliseconds,
  'awakenings': night.awakenings,
  'isMainSleep': night.isMainSleep,
  'timeInBedMs': night.timeInBed?.inMilliseconds,
  'efficiency': night.efficiency,
  'sources': night.sources.toList()..sort(),
};

HealthMetric _metric(Map<String, Object?> query) {
  final slug = query['metric']! as String;
  final metric = HealthMetric.fromSlug(slug);
  if (metric == null) throw StateError("unknown metric slug '$slug'");
  return metric;
}

String _date(DateTime day) =>
    '${_pad(day.year, 4)}-${_pad(day.month)}-${_pad(day.day)}';

/// `YYYY-MM-DDTHH:MM:SS+HH:MM` in the local zone — the shared instant encoding.
String _instant(DateTime at) {
  final local = at.toLocal();
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  return '${_date(local)}T${_pad(local.hour)}:${_pad(local.minute)}:'
      '${_pad(local.second)}$sign${_pad(abs.inHours)}:'
      '${_pad(abs.inMinutes.remainder(60))}';
}

String _pad(int value, [int width = 2]) => value.toString().padLeft(width, '0');
