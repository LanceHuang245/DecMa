import '../../l10n/generated/app_localizations.dart';

// Keep display labels separate from wire values; unknown levels show as-is.
String reasoningEffortLabel(AppLocalizations loc, String effort) =>
    switch (effort) {
      'low' => loc.effortLow,
      'medium' => loc.effortMedium,
      'high' => loc.effortHigh,
      'xhigh' => loc.effortXhigh,
      'max' => loc.effortMax,
      'ultra' => loc.effortUltra,
      _ => effort,
    };
