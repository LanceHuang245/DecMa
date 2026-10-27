import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.locale,
    required this.name,
  });

  final String code;
  final Locale locale;
  final String name;
}

const List<AppLanguage> appLanguages = [
  AppLanguage(code: 'en', locale: Locale('en'), name: 'English'),
  AppLanguage(code: 'zh', locale: Locale('zh'), name: '简体中文'),
];

// Supported locales passed to the app, in picker order.
final List<Locale> supportedLocales = appLanguages
    .map((e) => e.locale)
    .toList();

// The active language code; the app rebuilds its locale from this notifier.
final localeCodeNotifier = ValueNotifier<String>('zh');

Locale get appLocale =>
    appLanguages.firstWhere((l) => l.code == localeCodeNotifier.value).locale;

// Strings for code without a BuildContext, such as controllers and services.
AppLocalizations get appL10n => lookupAppLocalizations(appLocale);

// Prefer the saved choice, then the system language, then English.
String determineLocaleCode(String? saved) {
  if (saved != null && appLanguages.any((l) => l.code == saved)) return saved;
  final system = WidgetsBinding.instance.platformDispatcher.locale;
  return appLanguages
      .firstWhere(
        (l) => l.code == system.toString() || l.code == system.languageCode,
        orElse: () => appLanguages.firstWhere((l) => l.code == 'en'),
      )
      .code;
}
