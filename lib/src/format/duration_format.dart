/// Formats a [duration] compactly as `Hh Mm` (e.g. `7h 20m`, `45m`).
String formatHoursMinutes(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  return '${hours}h ${minutes}m';
}
