import 'package:cairn/src/sync/nextcloud_auth.dart';
import 'package:cairn/src/sync/nextcloud_sync_coordinator.dart';
import 'package:cairn/src/sync/nextcloud_sync_target.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// How long to keep polling for the user to finish authorising in the browser.
const Duration _pollTimeout = Duration(minutes: 5);

/// How long to wait between Login Flow v2 poll attempts.
const Duration _pollInterval = Duration(seconds: 2);

/// Guided "Connect your Nextcloud" screen (DESIGN.md §6): enter a host, open
/// Login Flow v2 in the system browser, and poll until the app password is
/// issued. Pops `true` once connected.
class ConnectNextcloudPage extends StatefulWidget {
  /// Creates the connect screen driven by [coordinator].
  const ConnectNextcloudPage({required this.coordinator, super.key});

  /// Drives the begin/poll/store steps.
  final NextcloudSyncCoordinator coordinator;

  @override
  State<ConnectNextcloudPage> createState() => _ConnectNextcloudPageState();
}

class _ConnectNextcloudPageState extends State<ConnectNextcloudPage> {
  final TextEditingController _hostController = TextEditingController();
  bool _busy = false;
  bool _polling = false;
  String _status = '';

  @override
  void dispose() {
    _polling = false;
    _hostController.dispose();
    super.dispose();
  }

  /// Normalises the typed host to an `https` [Uri], prepending the scheme when
  /// omitted. Returns `null` for empty input, an explicit `http://` (cleartext
  /// is refused), or anything without a host.
  Uri? _normaliseHost(String input) {
    final text = input.trim();
    if (text.isEmpty || text.startsWith('http://')) return null;
    final withScheme = text.startsWith('https://') ? text : 'https://$text';
    final uri = Uri.tryParse(withScheme);
    return (uri == null || uri.host.isEmpty) ? null : uri;
  }

  Future<void> _connect() async {
    final host = _normaliseHost(_hostController.text);
    if (host == null) {
      setState(() => _status = 'Enter your Nextcloud address (https).');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Starting login…';
    });
    try {
      final session = await widget.coordinator.begin(host);
      final launched = await launchUrl(
        session.loginUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _fail('Could not open the browser for login.');
        return;
      }
      if (!mounted) return;
      setState(() => _status = 'Waiting for browser authorisation…');
      await _pollUntilConnected(session);
    } on NextcloudSyncException catch (error) {
      _fail(error.message);
    } on FormatException catch (error) {
      _fail('Invalid host: ${error.message}');
    } on Exception catch (error) {
      // Fail-closed: any unexpected error must surface, never freeze the UI.
      _fail('Could not connect: $error');
    } finally {
      // Last resort: if a non-Exception Error escaped (it still propagates to
      // the zone handler), at least re-enable the UI so the button isn't stuck.
      if (mounted && (_busy || _polling)) {
        setState(() {
          _busy = false;
          _polling = false;
        });
      }
    }
  }

  Future<void> _pollUntilConnected(LoginFlowSession session) async {
    _polling = true;
    final deadline = DateTime.now().add(_pollTimeout);
    while (_polling && mounted && DateTime.now().isBefore(deadline)) {
      try {
        final credentials = await widget.coordinator.pollAndStore(session);
        if (credentials != null) {
          if (!mounted) return;
          Navigator.of(context).pop(true);
          return;
        }
      } on NextcloudSyncException catch (error) {
        if (!error.retryable) {
          _fail(error.message);
          return;
        }
        // Transient network/DNS/timeout blip (common on emulators) — show the
        // cause but keep polling until the deadline rather than aborting.
        if (mounted) {
          final cause = error.message;
          setState(() => _status = 'Network issue, retrying… ($cause)');
        }
      } on Exception catch (error) {
        // Fail-closed: e.g. a secure-storage PlatformException on the store
        // step must show a message, not leave the screen stuck "waiting".
        _fail('Could not complete connection: $error');
        return;
      }
      await Future<void>.delayed(_pollInterval);
    }
    if (_polling) _fail('Timed out waiting for authorisation.');
  }

  void _fail(String message) {
    _polling = false;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect your Nextcloud')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _hostController,
              enabled: !_busy,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Nextcloud address',
                hintText: 'cloud.example.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _connect,
              child: const Text('Connect'),
            ),
            const SizedBox(height: 16),
            if (_busy) const Center(child: CircularProgressIndicator()),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_status, textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
    );
  }
}
