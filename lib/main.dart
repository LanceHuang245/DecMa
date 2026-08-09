import 'package:fluent_ui/fluent_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'app_constants.dart';
import 'models/trading_models.dart';
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
  final initialLlmConnections = await settingsStore.readConnections();
  final initialMcp = await settingsStore.readMcp();
  final initialApi = await settingsStore.readApi();
  final initialNews = await settingsStore.readNews();
  final initialSymbol = await settingsStore.readLastViewedSymbol();
  runApp(
    DecmaApp(
      nodeAvailable: nodeAvailable,
      initialLlmConnections: initialLlmConnections,
      initialMcp: initialMcp,
      initialApi: initialApi,
      initialNews: initialNews,
      initialSymbol: initialSymbol,
    ),
  );
}

class DecmaApp extends StatelessWidget {
  const DecmaApp({
    super.key,
    this.nodeAvailable = true,
    this.initialLlmConnections,
    this.initialMcp,
    this.initialApi,
    this.initialNews,
    this.initialSymbol,
  });

  final bool nodeAvailable;
  final LlmConnectionSettings? initialLlmConnections;
  final McpSettings? initialMcp;
  final ApiSettings? initialApi;
  final NewsSettings? initialNews;
  final String? initialSymbol;

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: AppConstants.appName,
      themeMode: ThemeMode.dark,
      darkTheme: FluentThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.blue,
      ),
      home: DashboardPage(
        nodeAvailable: nodeAvailable,
        initialLlmConnections: initialLlmConnections,
        initialMcp: initialMcp,
        initialApi: initialApi,
        initialNews: initialNews,
        initialSymbol: initialSymbol,
      ),
    );
  }
}
