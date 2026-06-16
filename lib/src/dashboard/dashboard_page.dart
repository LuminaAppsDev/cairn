import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_package_repository.dart';
import 'package:cairn/src/storage/health_ingest_service.dart';
import 'package:cairn/src/storage/jsonl_omh_file_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The app's home screen.
///
/// In v1 this reads the local Open mHealth cache and renders the in-app
/// dashboard (DESIGN.md §9, read/display path A). For now it is a placeholder
/// that — in debug builds only — exposes a manual "read & persist" harness for
/// the Phase 1/2 on-device exit checks (DESIGN.md §15). It is not product UI.
class DashboardPage extends StatefulWidget {
  /// Creates the dashboard page.
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _status = '';
  bool _running = false;

  Future<void> _readAndPersist() async {
    // Debug-only: never read, persist, or log health data in release builds.
    assert(kDebugMode, 'read-health harness is debug-only');
    if (!kDebugMode) return;
    setState(() {
      _running = true;
      _status = 'Authorising…';
    });

    final lines = <String>[];
    try {
      final repository = HealthPackageRepository();
      final granted = await repository.requestAuthorization(
        HealthMetric.values.toSet(),
      );
      final store = await JsonlOmhFileStore.appDocuments();
      final ingest = HealthIngestService(repository: repository, store: store);
      final results = await ingest.ingest(granted);

      final now = DateTime.now();
      final from = now.subtract(const Duration(days: 31));
      for (final result in results) {
        final onDisk = await store.readRange(
          metric: result.metric,
          from: from,
          to: now,
        );
        final line =
            '${result.metric.name}: +${result.dataPointCount} written, '
            '${onDisk.length} on disk';
        lines.add(line);
        debugPrint(line);
      }
      for (final metric in HealthMetric.values) {
        if (!granted.contains(metric)) {
          final line = '${metric.name}: not granted';
          lines.add(line);
          debugPrint(line);
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
                onPressed: _running ? null : _readAndPersist,
                child: const Text('Read & persist (debug)'),
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
