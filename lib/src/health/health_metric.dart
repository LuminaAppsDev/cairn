/// The health measures Cairn maps in v1 (DESIGN.md §5.2).
///
/// Each value corresponds to a single Open mHealth / IEEE 1752.1 schema and a
/// dedicated on-disk shard (`/Cairn/<metric>/<year>/<date>.jsonl`).
enum HealthMetric {
  /// Heart rate, in beats per minute.
  heartRate,

  /// Cumulative step count.
  steps,

  /// Sleep episodes and their duration.
  sleep,

  /// Physical activity and workouts.
  activity,

  /// Body weight, in kilograms.
  weight;

  /// Stable on-disk slug for this metric — the shard directory name and the
  /// `manifest.json` anchor key (DESIGN.md §5.3). Part of the file format, so
  /// changing it is a breaking change.
  String get slug => switch (this) {
    HealthMetric.heartRate => 'heart-rate',
    HealthMetric.steps => 'steps',
    HealthMetric.sleep => 'sleep',
    HealthMetric.activity => 'activity',
    HealthMetric.weight => 'weight',
  };

  /// The metric for [slug], or `null` if unknown (e.g. a slug from a newer
  /// format version).
  static HealthMetric? fromSlug(String slug) => switch (slug) {
    'heart-rate' => HealthMetric.heartRate,
    'steps' => HealthMetric.steps,
    'sleep' => HealthMetric.sleep,
    'activity' => HealthMetric.activity,
    'weight' => HealthMetric.weight,
    _ => null,
  };
}
