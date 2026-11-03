import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/health/health_source.dart';

/// A per-metric source-priority policy (DESIGN.md §4.3).
///
/// The same metric often arrives from several sources (phone + watch + vendor
/// app) and double-counts. For each metric, [preferredSources] lists
/// case-insensitive source-name fragments in priority order (most preferred
/// first); a sample whose source matches an earlier fragment wins.
class SourcePriorityPolicy {
  /// Creates a policy from a metric → ordered source-fragment map.
  const new(this.preferredSources);

  /// Sensible defaults: prefer wearables for sensed metrics. Weight has no
  /// source preference (you typically weigh once), so it falls back to the
  /// recording-method tie-break.
  const new defaults()
    : preferredSources = const {
        HealthMetric.heartRate: _wearables,
        HealthMetric.steps: _wearables,
        HealthMetric.sleep: _wearables,
        HealthMetric.activity: _wearables,
      };

  static const List<String> _wearables = [
    'watch',
    'wear',
    'band',
    'fit',
    'tracker',
  ];

  /// Ordered, most-preferred-first source-name fragments per metric.
  final Map<HealthMetric, List<String>> preferredSources;

  /// Priority rank of [source] for [metric] — lower is higher priority.
  /// Unmatched sources share the lowest priority.
  int rank(HealthMetric metric, HealthSource source) {
    final order = preferredSources[metric] ?? const [];
    final name = source.name.toLowerCase();
    for (var i = 0; i < order.length; i++) {
      if (name.contains(order[i].toLowerCase())) return i;
    }
    return order.length;
  }
}

/// Collapses competing readings of the same metric and time window down to a
/// single preferred-source reading (DESIGN.md §4.3).
///
/// Readings are keyed by `(metric, start, end)` to whole-second precision;
/// within a key the highest-priority source wins, with automatically-recorded
/// readings preferred over manual ones on a tie.
class SourcePriorityDeduplicator {
  /// Creates a deduplicator with the given [policy].
  const new({this.policy = const SourcePriorityPolicy.defaults()});

  /// The source-priority policy applied on collisions.
  final SourcePriorityPolicy policy;

  /// Returns [samples] with competing same-window readings collapsed.
  List<HealthSample> deduplicate(List<HealthSample> samples) {
    final best = <String, HealthSample>{};
    for (final sample in samples) {
      final key = _key(sample);
      final current = best[key];
      if (current == null || _prefer(sample, current)) {
        best[key] = sample;
      }
    }
    return best.values.toList();
  }

  bool _prefer(HealthSample candidate, HealthSample current) {
    final rc = policy.rank(candidate.metric, candidate.source);
    final rk = policy.rank(current.metric, current.source);
    if (rc != rk) return rc < rk;
    return _manualPenalty(candidate.source) < _manualPenalty(current.source);
  }

  int _manualPenalty(HealthSource source) =>
      source.recordingMethod == RecordingMethodKind.manual ? 1 : 0;

  String _key(HealthSample s) =>
      '${s.metric.name}|${_seconds(s.start)}|${_seconds(s.end)}';

  int _seconds(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000;
}
