/// Whether the health store may be read while the app is in the background —
/// on Android a separate Health Connect permission
/// (`READ_HEALTH_DATA_IN_BACKGROUND`), without which such a read may fail.
enum BackgroundReadStatus {
  /// No such permission exists (iOS): background reads need nothing extra.
  notApplicable,

  /// This Health Connect lacks the background-read feature, so it can't be
  /// granted at all.
  unavailable,

  /// Available, but not granted (yet).
  missing,

  /// Granted.
  granted;

  /// Whether a background run may read the health store.
  bool get allowsBackgroundReads => this == notApplicable || this == granted;
}
