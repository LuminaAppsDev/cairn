import 'dart:convert';

import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_package_repository.dart';
import 'package:cairn/src/omh/default_omh_mapper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The app's home screen.
///
/// In v1 this reads the local Open mHealth cache and renders the in-app
/// dashboard (DESIGN.md §9, read/display path A). For now it is a placeholder
/// that — in debug builds only — exposes a manual "read health now" harness for
/// the Phase 1 on-device exit check (DESIGN.md §15). It is not product UI.
class DashboardPage extends StatefulWidget {
  /// Creates the dashboard page.
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _status = '';
  bool _running = false;

  Future<void> _readHealthNow() async {
    // Debug-only: never read or log health data in profile/release builds.
    assert(kDebugMode, 'read-health harness is debug-only');
    if (!kDebugMode) return;
    setState(() {
      _running = true;
      _status = 'Requesting authorisation…';
    });

    final repository = HealthPackageRepository();
    final mapper = DefaultOmhMapper();
    final lines = <String>[];
    try {
      final granted = await repository.requestAuthorization(
        HealthMetric.values.toSet(),
      );
      final end = DateTime.now();
      final start = end.subtract(const Duration(days: 1));
      for (final metric in HealthMetric.values) {
        if (!granted.contains(metric)) {
          const suffix = ': not granted';
          lines.add('${metric.name}$suffix');
          debugPrint('${metric.name}$suffix');
          continue;
        }
        final samples = await repository.readSamples(
          metric: metric,
          start: start,
          end: end,
        );
        final line = '${metric.name}: ${samples.length} sample(s)';
        lines.add(line);
        debugPrint(line);
        if (samples.isNotEmpty) {
          final encoded = jsonEncode(mapper.toDataPoint(samples.first));
          debugPrint('  first → $encoded');
        }
      }
    } on Exception catch (error) {
      lines.add('error: $error');
    }

    if (!mounted) return;
    setState(() {
      _running = false;
      _status = lines.join('\n');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cairn')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Cairn'),
            if (kDebugMode) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _running ? null : _readHealthNow,
                child: const Text('Read health now (debug)'),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(_status, textAlign: TextAlign.center),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
