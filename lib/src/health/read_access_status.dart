/// Whether one of Health Connect's additional read permissions is held: reads
/// in the background (`READ_HEALTH_DATA_IN_BACKGROUND`, without which such a
/// read may fail) or of data older than 30 days before the first grant
/// (`READ_HEALTH_DATA_HISTORY`, without which such data reads as absent).
enum ReadAccessStatus {
  /// No such permission exists (iOS): the access needs nothing extra.
  notApplicable,

  /// This Health Connect lacks the feature, so it can't be granted at all.
  unavailable,

  /// Available, but not granted (yet).
  missing,

  /// Granted.
  granted;

  /// Whether the access is allowed.
  bool get allowed => this == notApplicable || this == granted;
}
