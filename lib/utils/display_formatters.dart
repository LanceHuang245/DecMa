/// Formats a market price for compact dashboard and trade-plan displays.
String formatMarketPrice(double value) {
  if (value >= 1000) return value.toStringAsFixed(1);
  if (value >= 1) return value.toStringAsFixed(4);
  return value.toStringAsFixed(6);
}

/// Formats a local time for compact event and news rows.
String formatLocalTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Formats a local date for the chart time axis.
String formatLocalDate(DateTime value) {
  final local = value.toLocal();
  return '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

/// Formats a local date and time for chart tooltips.
String formatLocalDateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Creates a non-secret placeholder for a key stored in secure storage.
String? createSecretMask(bool hasSavedKey) =>
    hasSavedKey ? 'saved-secret' : null;
