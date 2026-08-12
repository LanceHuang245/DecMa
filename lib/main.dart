import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app_constants.dart';
import 'providers/app_providers.dart';
import 'services/llm_settings_store.dart';
import 'services/node_runtime_service.dart';
import 'ui/dashboard/dashboard_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1540, 900),
    minimumSize: Size(1540, 900),
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
    return FluentApp(
      title: AppConstants.appName,
      themeMode: ThemeMode.dark,
      darkTheme: FluentThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.blue,
      ),
      home: const DashboardPage(),
    );
  }
}
