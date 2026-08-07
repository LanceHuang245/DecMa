import 'package:fluent_ui/fluent_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'models/trading_models.dart';
import 'services/node_runtime_service.dart';
import 'services/llm_settings_store.dart';
import 'widgets/dashboard_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1280, 800),
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
  final initialLlm = await LlmSettingsStore().read();
  runApp(DecmaApp(nodeAvailable: nodeAvailable, initialLlm: initialLlm));
}

class DecmaApp extends StatelessWidget {
  const DecmaApp({super.key, this.nodeAvailable = true, this.initialLlm});

  final bool nodeAvailable;
  final LlmSettings? initialLlm;

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'DecMa',
      themeMode: ThemeMode.dark,
      darkTheme: FluentThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.blue,
      ),
      home: DashboardPage(nodeAvailable: nodeAvailable, initialLlm: initialLlm),
    );
  }
}
