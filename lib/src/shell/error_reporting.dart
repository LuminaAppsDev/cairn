import 'package:flutter/foundation.dart';

/// Hands a caught [error] to Flutter's error machinery when it is a bug rather
/// than an anticipated failure.
///
/// The UI catches `Object`, not `Exception`, so that nothing can escape and
/// strand a spinner — the health plugin, for one, reports a missing Health
/// Connect with an `UnsupportedError`. The cost of that width is that a genuine
/// programming bug — a `TypeError`, a failed assertion — would land in the same
/// bucket and be shown to the user as a benign "could not read", with only a
/// `debugPrint` left behind for the maintainer.
///
/// So: an `Exception` is an expected outcome and passes silently; anything else
/// is reported where uncaught errors already go. It is *reported*, not
/// rethrown, so the caller still returns its typed failure and the user still
/// gets a message.
///
/// Reach is deliberately local: Cairn wires no crash reporting, by design, so
/// this lands in the debug console and in `logcat` on a release build — not in
/// anyone's inbox. That is enough to make a bug visible to whoever is looking
/// at the device, and it is the most an app that sends nothing anywhere can do.
void reportIfBug(Object error, StackTrace stack, {required String whileDoing}) {
  if (error is Exception) return;
  reportBug(error, stack, whileDoing: whileDoing);
}

/// Hands [error] to Flutter's error machinery as a bug, whatever its type —
/// for an `Exception` the caller knows to be one, such as a health read the
/// plugin failed through a fault of its own. Reach as for [reportIfBug]. Its
/// text can quote a native message, and a plugin fault's message could quote a
/// record value: keep this local-only if crash reporting is ever wired in.
void reportBug(Object error, StackTrace stack, {required String whileDoing}) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'cairn',
      context: ErrorDescription(whileDoing),
    ),
  );
}
