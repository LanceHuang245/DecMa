import 'package:fluent_ui/fluent_ui.dart';

import 'services/node_runtime_service.dart';
import 'widgets/dashboard_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final nodeAvailable = await NodeRuntimeService.isAvailable();
  runApp(DecmaApp(nodeAvailable: nodeAvailable));
}

class DecmaApp extends StatelessWidget {
  const DecmaApp({super.key, this.nodeAvailable = true});

  final bool nodeAvailable;

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'DecMa',
      themeMode: ThemeMode.dark,
      darkTheme: FluentThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.blue,
      ),
      home: DashboardPage(nodeAvailable: nodeAvailable),
    );
  }
}
