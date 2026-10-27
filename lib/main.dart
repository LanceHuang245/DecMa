import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app_constants.dart';
import 'l10n/app_languages.dart';
import 'l10n/generated/app_localizations.dart';
import 'providers/app_providers.dart';
import 'data/services/storage/llm_settings_store.dart';
import 'data/services/node_runtime_service.dart';
import 'ui/dashboard/dashboard_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1280, 700),
    minimumSize: Size(1280, 700),
    center: true,
    titleBarStyle: TitleBarStyle.hidden,
  );
  // Hide the native title bar before Flutter paints the Fluent replacement.
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.show();
    await windowManager.focus();
  });
  final nodeAvailable = await NodeRuntimeService.isAvailable();
  final settingsStore = LlmSettingsStore();
  localeCodeNotifier.value = determineLocaleCode(
    await settingsStore.readLocaleCode(),
  );
  final initialSettings = AppInitialSettings(
    nodeAvailable: nodeAvailable,
    llmConnections: await settingsStore.readConnections(),
    mcp: await settingsStore.readMcp(),
    api: await settingsStore.readApi(),
    news: await settingsStore.readNews(),
    symbol: await settingsStore.readLastViewedSymbol(),
  );
  runApp(
    ProviderScope(
      overrides: [
        appInitialSettingsProvider.overrideWithValue(initialSettings),
      ],
      child: const DecmaApp(),
    ),
  );
}

class DecmaApp extends StatelessWidget {
  const DecmaApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuild the app locale whenever the language picker changes it.
    return ValueListenableBuilder<String>(
      valueListenable: localeCodeNotifier,
      builder: (context, _, _) => FluentApp(
        title: AppConstants.appName,
        locale: appLocale,
        supportedLocales: supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        themeMode: ThemeMode.dark,
        darkTheme: FluentThemeData(
          brightness: Brightness.dark,
          accentColor: Colors.blue,
        ),
        home: const DashboardPage(),
      ),
    );
  }
}
