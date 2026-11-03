import 'package:cairn/src/health/background_read_status.dart';
import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_sample.dart';

/// Read-only access to the OS health store (Apple HealthKit / Android Health
/// Connect).
///
/// Cairn only ever reads; it never writes back to the health store
/// (DESIGN.md §2, §4.1). This interface isolates the native capability so it
/// can be mocked in tests (DESIGN.md §13). Implementations wrap the `health`
/// package.
abstract interface class HealthRepository {
  /// Whether the OS health store is present and usable on this device.
  ///
  /// `false` only on Android, when Health Connect is missing or its provider
  /// needs an update. Every read then fails, so the UI reports it as its own
  /// outcome rather than as a generic read error.
  Future<bool> isAvailable();

  /// Requests read authorisation for [metrics] and returns the subset granted.
  ///
  /// Callers must handle partial grants gracefully and must not depend on a
  /// single boolean: iOS deliberately hides read-authorisation status, so
  /// design around data presence instead (DESIGN.md §4.2).
  Future<Set<HealthMetric>> requestAuthorization(Set<HealthMetric> metrics);

  /// Reads samples of [metric] recorded within the half-open window
  /// `[start, end)`.
  ///
  /// An empty list means the store holds no data in the window. A read the
  /// store fails throws [HealthReadException] instead — never an empty list,
  /// which callers would mistake for "nothing there" and skip past for good.
  Future<List<HealthSample>> readSamples({
    required HealthMetric metric,
    required DateTime start,
    required DateTime end,
  });

  /// Whether the store may be read while the app is in the background — what
  /// a background sync checks before it tries.
  Future<BackgroundReadStatus> backgroundReadStatus();

  /// Asks for background reads (Health Connect's sheet on Android) and returns
  /// the status afterwards. Only meaningful while it is
  /// [BackgroundReadStatus.missing].
  Future<BackgroundReadStatus> requestBackgroundRead();
}

/// Thrown when the OS health store cannot be reached at all — on Android, when
/// Health Connect is absent or its provider needs an update.
///
/// Distinct from a failed *read*: nothing is wrong with the request, the store
/// simply is not there, and the user has to act on the device before any read
/// can work.
class HealthStoreUnavailableException implements Exception {
  /// Creates the exception.
  const HealthStoreUnavailableException();

  @override
  String toString() =>
      'HealthStoreUnavailableException: '
      'the OS health store is not available on this device';
}

/// What a failed read says about its cause, which decides how ingest reacts.
enum HealthReadFailure {
  /// The store's state, likely to pass: a binder failure, a permission revoked
  /// mid-run, HealthKit's database locked. The next refresh retries.
  transient,

  /// The store's read quota is spent. Every further read now would fail too,
  /// and spend more of it, so the run stops.
  rateLimited,

  /// A fault in the plugin or in Cairn's request, such as a record the plugin
  /// can't convert. It fails the same way every run until a fix ships, so it
  /// is reported as a bug.
  unexpected,
}

/// Thrown when the OS health store fails a read of [metric] — a rate limit, a
/// permission revoked mid-run, a background read without the background
/// permission, or HealthKit's database being locked.
///
/// Distinct from an *empty* read: the data may well be there, so the sync
/// anchor must stay put and a later run must retry the window.
class HealthReadException implements Exception {
  /// Creates the exception for a failed read of [metric].
  const HealthReadException(
    this.metric, {
    this.code,
    this.message,
    this.failure = HealthReadFailure.transient,
  });

  /// The metric whose read failed.
  final HealthMetric metric;

  /// What the failure says about its cause.
  final HealthReadFailure failure;

  /// The platform's error code, for logs (e.g. `HEALTH_READ_FAILED`).
  final String? code;

  /// The platform's description, for logs only — on Android the native
  /// exception's class and message, which tell a rate limit from a revoked
  /// permission. Never shown in the UI, and must never carry record contents
  /// (re-check on plugin upgrades: third_party/health/CAIRN_PATCHES.md).
  final String? message;

  @override
  String toString() =>
      'HealthReadException: reading ${metric.name} failed '
      '(${code ?? '?'}${message == null ? '' : ': $message'})';
}
