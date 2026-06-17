import 'dart:async';

import 'package:cairn/src/dashboard/connect_nextcloud_page.dart';
import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/profile/profile.dart';
import 'package:cairn/src/shell/cairn_services.dart';
import 'package:cairn/src/storage/health_ingest_service.dart';
import 'package:cairn/src/sync/nextcloud_sync_target.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Product settings: Nextcloud connection + manual sync, the profile editor
/// (height + date of birth for BMI), and a debug-only developer section.
class SettingsPage extends StatefulWidget {
  /// Creates the settings page.
  const SettingsPage({required this.services, super.key});

  /// Shared app services.
  final CairnServices services;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _height = TextEditingController();
  String _connection = 'Checking…';
  String _syncStatus = '';
  String _debugStatus = '';
  Profile _profile = Profile.empty();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _height.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final credentials = await widget.services.coordinator.currentCredentials();
    final profile = await widget.services.profileStore.read();
    if (!mounted) return;
    setState(() {
      _connection = credentials == null
          ? 'Not connected'
          : '${credentials.loginName}@${credentials.server.host}';
      _profile = profile;
      _height.text = profile.heightCm == null
          ? ''
          : profile.heightCm!.toStringAsFixed(0);
    });
  }

  Future<void> _connect() async {
    final connected = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            ConnectNextcloudPage(coordinator: widget.services.coordinator),
      ),
    );
    if (connected ?? false) await _load();
  }

  Future<void> _disconnect() async {
    await widget.services.coordinator.disconnect();
    if (!mounted) return;
    setState(() => _syncStatus = '');
    await _load();
  }

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _syncStatus = 'Syncing…';
    });
    String status;
    try {
      if (!await widget.services.coordinator.isConnected()) {
        status = 'Connect a Nextcloud first.';
      } else {
        final report = await widget.services.coordinator.syncNow();
        final conflicts = report.hasConflicts
            ? ' · ${report.conflicts.length} conflicts'
            : '';
        status =
            '${report.pushed.length} pushed, '
            '${report.skipped} up to date$conflicts';
      }
    } on NextcloudSyncException catch (e) {
      status = 'Sync failed: ${e.message}';
    } on Exception catch (e) {
      status = 'Sync failed: $e';
    }
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _syncStatus = status;
    });
  }

  Future<void> _saveHeight() async {
    final text = _height.text.trim();
    double? value;
    if (text.isNotEmpty) {
      final parsed = double.tryParse(text);
      // Reject non-finite (`Infinity`/`NaN` parse) and implausible heights;
      // a non-finite value would also crash the JSON encoder on write.
      if (parsed == null || !parsed.isFinite || parsed < 30 || parsed > 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter a height between 30 and 300 cm.'),
          ),
        );
        return;
      }
      value = parsed;
    }
    // Construct directly (not copyWith) so a blank field clears the height.
    final next = Profile(
      heightCm: value,
      dateOfBirth: _profile.dateOfBirth,
    );
    await widget.services.profileStore.write(next);
    if (!mounted) return;
    setState(() => _profile = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value == null ? 'Height cleared' : 'Height saved'),
      ),
    );
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _profile.dateOfBirth ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked == null) return;
    final next = _profile.copyWith(dateOfBirth: picked);
    await widget.services.profileStore.write(next);
    if (!mounted) return;
    setState(() => _profile = next);
  }

  Future<void> _ingestDebug() async {
    setState(() => _debugStatus = 'Reading…');
    final lines = <String>[];
    try {
      final repo = widget.services.repository;
      final granted = await repo.requestAuthorization(
        HealthMetric.values.toSet(),
      );
      final results = await HealthIngestService(
        repository: repo,
        store: widget.services.store,
      ).ingest(granted);
      for (final r in results) {
        lines.add('${r.metric.name}: +${r.dataPointCount}');
      }
    } on Exception catch (e) {
      lines.add('error: $e');
    }
    if (!mounted) return;
    setState(() => _debugStatus = lines.join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dob = _profile.dateOfBirth;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Nextcloud', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_connection),
                  if (_syncStatus.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_syncStatus, style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _syncing ? null : _connect,
                        child: const Text('Connect'),
                      ),
                      OutlinedButton(
                        onPressed: _syncing ? null : _disconnect,
                        child: const Text('Disconnect'),
                      ),
                      FilledButton(
                        onPressed: _syncing ? null : _syncNow,
                        child: const Text('Sync now'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Profile', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Used to compute your BMI from the latest synced weight. Stored in '
            'your Nextcloud.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _height,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Height',
                            suffixText: 'cm',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _saveHeight,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Date of birth'),
                    subtitle: Text(
                      dob == null
                          ? 'Not set'
                          : '${dob.year}-${_two(dob.month)}-${_two(dob.day)}',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: _pickDob,
                  ),
                ],
              ),
            ),
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 24),
            Text('Developer', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _ingestDebug,
              child: const Text('Ingest from health store'),
            ),
            if (_debugStatus.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_debugStatus, style: theme.textTheme.bodySmall),
              ),
          ],
        ],
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
