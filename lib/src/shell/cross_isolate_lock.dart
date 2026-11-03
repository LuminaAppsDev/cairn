import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

/// A mutex shared by every isolate in the process — the UI isolate and the
/// background-sync isolate (WorkManager / BGTaskScheduler), which run in the
/// same process but share no memory.
///
/// Built on [IsolateNameServer]: its name-to-port mapping is process-wide
/// (Flutter engines share one Dart VM), and registering a name is an atomic
/// test-and-set that fails while the name is taken. File locks wouldn't do:
/// POSIX record locks are per process, so two isolates never exclude each
/// other. The holder registers its isolate's control port, so it is not
/// reentrant within one isolate.
///
/// It coordinates; it is not what keeps files whole. Every write it guards is
/// an atomic per-writer temp + rename, so even an overlap costs at most a
/// deduplicated re-read — which is what lets it be lenient about holders that
/// can't release:
///
/// * A holder whose isolate died — Android destroys a background engine when
///   WorkManager stops the worker, with no `finally` run — is detected by two
///   unanswered pings at [Isolate.immediate] priority (answered by the VM even
///   mid-computation) and taken over. Two, because after an iOS suspension the
///   first answer can arrive late.
/// * A holder that is alive but hung is taken over by [run] after [maxWait] —
///   never sooner: a live, working holder must not be overlapped, since a
///   shard compaction's rename would drop the other refresh's appends.
final class CrossIsolateLock {
  /// Creates a lock identified by [name]; every isolate using the same name
  /// shares it.
  CrossIsolateLock(
    this.name, {
    this.pollInterval = const Duration(milliseconds: 250),
    this.staleAfter = const Duration(seconds: 10),
    this.pingTimeout = const Duration(seconds: 2),
    this.maxWait = const Duration(minutes: 15),
  });

  /// The process-wide name the lock is registered under.
  final String name;

  /// How long a waiter sleeps between attempts while the lock is held.
  final Duration pollInterval;

  /// How long one holder may keep the lock before a waiter checks it is alive.
  final Duration staleAfter;

  /// How long each liveness ping may go unanswered.
  final Duration pingTimeout;

  /// The longest [run] waits for a live holder before taking over anyway.
  /// Longer than any legitimate hold — WorkManager stops a worker after 10
  /// minutes, iOS a background task after about 30 s — so it only ever
  /// breaks a hang, never a slow but working sync.
  final Duration maxWait;

  SendPort get _self => Isolate.current.controlPort;

  /// Runs [action] while holding the lock, first waiting for another holder
  /// in the process to finish — taking over from one that died, or that is
  /// still holding after [maxWait]. Releases the lock however [action] ends.
  Future<T> run<T>(Future<T> Function() action) async {
    await _acquire();
    return _holding(action);
  }

  /// Runs [action] only if the lock is free, or held by an isolate that has
  /// died; returns `null` without running it while a live holder has it.
  /// Never waits for that holder to finish.
  Future<T?> tryRun<T>(Future<T> Function() action) async {
    if (!_register()) {
      final holder = IsolateNameServer.lookupPortByName(name);
      if (holder != null && !await _isDead(holder)) return null;
      _takeOver(holder);
      if (!_register()) return null; // another party got there first
    }
    return _holding(action);
  }

  Future<T> _holding<T>(Future<T> Function() action) async {
    try {
      return await action();
    } finally {
      if (IsolateNameServer.lookupPortByName(name) == _self) {
        IsolateNameServer.removePortNameMapping(name);
      }
    }
  }

  Future<void> _acquire() async {
    final waited = Stopwatch()..start();
    final held = Stopwatch()..start();
    SendPort? holder;
    while (!_register()) {
      final current = IsolateNameServer.lookupPortByName(name);
      if (current != holder) {
        holder = current;
        held.reset();
      }
      if (current != null &&
          (waited.elapsed >= maxWait ||
              (held.elapsed >= staleAfter &&
                  await _checkStale(current, held)))) {
        _takeOver(current);
        continue;
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  // Pings a long holder; an answer restarts its clock, so a live holder is
  // pinged once per [staleAfter], not on every poll.
  Future<bool> _checkStale(SendPort holder, Stopwatch held) async {
    if (await _isDead(holder)) return true;
    held.reset();
    return false;
  }

  bool _register() => IsolateNameServer.registerPortWithName(_self, name);

  // Clears the mapping only if it still names [holder]; anyone else who took
  // over meanwhile keeps theirs.
  void _takeOver(SendPort? holder) {
    if (IsolateNameServer.lookupPortByName(name) == holder) {
      IsolateNameServer.removePortNameMapping(name);
    }
  }

  Future<bool> _isDead(SendPort holder) async =>
      !await _answers(holder) && !await _answers(holder);

  Future<bool> _answers(SendPort holder) async {
    final reply = ReceivePort();
    try {
      // ping's default priority is Isolate.immediate: answered even mid-work.
      Isolate(holder).ping(reply.sendPort);
      await reply.first.timeout(pingTimeout);
      return true;
    } on TimeoutException {
      return false;
    } finally {
      reply.close();
    }
  }
}
