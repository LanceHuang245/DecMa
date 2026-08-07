import 'package:fluent_ui/fluent_ui.dart';

import 'widgets/dashboard_page.dart';

void main() {
  runApp(const DecmaApp());
}

class DecmaApp extends StatelessWidget {
  const DecmaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'DecMa',
      themeMode: ThemeMode.dark,
      darkTheme: FluentThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.blue,
      ),
      home: const DashboardPage(),
    );
  }
}
