import 'package:fluent_ui/fluent_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'models/trading_models.dart';
import 'services/node_runtime_service.dart';
import 'services/llm_settings_store.dart';
import 'ui/dashboard/dashboard_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(1280, 800),
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
  final initialLlm = await settingsStore.read();
  final initialMcp = await settingsStore.readMcp();
  final initialApi = await settingsStore.readApi();
  runApp(
    DecmaApp(
      nodeAvailable: nodeAvailable,
      initialLlm: initialLlm,
      initialMcp: initialMcp,
      initialApi: initialApi,
    ),
  );
}

class DecmaApp extends StatelessWidget {
  const DecmaApp({
    super.key,
    this.nodeAvailable = true,
    this.initialLlm,
    this.initialMcp,
    this.initialApi,
  });

  final bool nodeAvailable;
  final LlmSettings? initialLlm;
  final McpSettings? initialMcp;
  final ApiSettings? initialApi;

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'DecMa',
      themeMode: ThemeMode.dark,
      darkTheme: FluentThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.blue,
      ),
      home: DashboardPage(
        nodeAvailable: nodeAvailable,
        initialLlm: initialLlm,
        initialMcp: initialMcp,
        initialApi: initialApi,
      ),
    );
  }
}
