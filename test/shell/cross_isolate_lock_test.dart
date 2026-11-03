import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:cairn/src/shell/cross_isolate_lock.dart';
import 'package:flutter_test/flutter_test.dart';

const _name = 'cairn.test.lock';

/// Spawned-isolate entry: takes the lock, reports `'held'`, then holds it
/// until told to let go, and reports `'released'`.
Future<void> _holdInOtherIsolate(SendPort main) async {
  final commands = ReceivePort();
  final letGo = commands.first;
  await CrossIsolateLock(_name).run(() async {
    main.send(['held', commands.sendPort]);
    await letGo;
  });
  main.send(['released']);
  commands.close();
}

void main() {
  tearDown(() => IsolateNameServer.removePortNameMapping(_name));

  test('a second holder waits until the first has finished', () async {
    final first = CrossIsolateLock(_name);
    // The first holds well past staleAfter, so the second really pings it —
    // and must not mistake the live, answering holder for dead.
    final second = CrossIsolateLock(
      _name,
      pollInterval: const Duration(milliseconds: 10),
      staleAfter: const Duration(milliseconds: 100),
      pingTimeout: const Duration(milliseconds: 100),
    );
    final events = <String>[];
    final release = Completer<void>();

    final firstRun = first.run(() async {
      events.add('first in');
      await release.future;
      events.add('first out');
    });
    final secondRun = second.run(() async => events.add('second in'));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(events, ['first in']);

    release.complete();
    await Future.wait([firstRun, secondRun]);
    expect(events, ['first in', 'first out', 'second in']);
  });

  test('a holder that died without releasing is taken over', () async {
    // A closed port never answers — like a background isolate the OS stopped
    // mid-refresh, whose mapping outlives it.
    final dead = ReceivePort()..close();
    IsolateNameServer.registerPortWithName(dead.sendPort, _name);
    final lock = CrossIsolateLock(
      _name,
      pollInterval: const Duration(milliseconds: 10),
      staleAfter: const Duration(milliseconds: 50),
      pingTimeout: const Duration(milliseconds: 50),
    );

    expect(await lock.run(() async => 42), 42);
  });

  test('background tryRun also takes over a dead holder', () async {
    // Android destroys a stopped worker's engine without running `finally`;
    // the background must not then skip every later run.
    final dead = ReceivePort()..close();
    IsolateNameServer.registerPortWithName(dead.sendPort, _name);
    final lock = CrossIsolateLock(
      _name,
      pingTimeout: const Duration(milliseconds: 50),
    );

    expect(await lock.tryRun(() async => 'ran'), 'ran');
  });

  test('a live but stuck holder is taken over after maxWait', () async {
    final stuck = Completer<void>();
    addTearDown(stuck.complete);
    unawaited(CrossIsolateLock(_name).run(() => stuck.future));
    final lock = CrossIsolateLock(
      _name,
      pollInterval: const Duration(milliseconds: 10),
      maxWait: const Duration(milliseconds: 100),
    );

    expect(await lock.run(() async => 'ran'), 'ran');
  });

  test('the lock is released even when the action throws', () async {
    final lock = CrossIsolateLock(_name);

    await expectLater(
      lock.run<void>(() async => throw StateError('boom')),
      throwsStateError,
    );
    expect(IsolateNameServer.lookupPortByName(_name), isNull);
    expect(await lock.run(() async => 'again'), 'again');
  });

  test('tryRun skips while the lock is held, and runs once free', () async {
    final release = Completer<void>();
    final held = CrossIsolateLock(_name).run(() => release.future);
    final lock = CrossIsolateLock(_name);

    expect(await lock.tryRun(() async => 'ran'), isNull);
    release.complete();
    await held;
    expect(await lock.tryRun(() async => 'ran'), 'ran');
  });

  test('a holder in another isolate excludes this one', () async {
    final messages = ReceivePort();
    final inbox = StreamIterator(messages);
    await Isolate.spawn(_holdInOtherIsolate, messages.sendPort);

    expect(await inbox.moveNext(), isTrue);
    final held = inbox.current as List<Object?>;
    expect(held.first, 'held');
    final lock = CrossIsolateLock(_name);
    expect(await lock.tryRun(() async => 'ran'), isNull);

    (held.last! as SendPort).send('let go');
    expect(await inbox.moveNext(), isTrue);
    expect((inbox.current as List<Object?>).single, 'released');
    expect(await lock.tryRun(() async => 'ran'), 'ran');
    await inbox.cancel();
  });
}
