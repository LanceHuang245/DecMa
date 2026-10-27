import 'package:fluent_ui/fluent_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../app_constants.dart';
import '../l10n/generated/app_localizations.dart';
import 'dashboard/dashboard_page.dart';
import 'settings/settings_page.dart';

// Microsoft Store style shell: compact icon pane, Home on top, Settings in the footer.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return NavigationView(
      // Round only the content's top-leading corner, like Windows 11 Settings.
      contentShape: const RoundedRectangleBorder(
        side: BorderSide(width: 0, color: Colors.transparent),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(8)),
      ),
      // The title bar replaces the hidden native one, including caption buttons.
      // 48px title bar and 64px compact pane, roomier than the 32/50 defaults.
      titleBar: TitleBar(
        height: 48,
        isBackButtonVisible: false,
        leftHeader: const Padding(
          padding: EdgeInsetsDirectional.only(start: 14),
          child: Text(AppConstants.appName, style: TextStyle(fontSize: 12)),
        ),
        captionControls: SizedBox(
          width: 138,
          height: 48,
          child: WindowCaption(
            brightness: FluentTheme.of(context).brightness,
            backgroundColor: Colors.transparent,
          ),
        ),
        onDragStarted: windowManager.startDragging,
        onDoubleTap: () async {
          if (await windowManager.isMaximized()) {
            await windowManager.unmaximize();
          } else {
            await windowManager.maximize();
          }
        },
      ),
      pane: NavigationPane(
        selected: _index,
        onChanged: (index) => setState(() => _index = index),
        displayMode: PaneDisplayMode.compact,
        // Always compact: drop the expand/collapse button and its slot.
        toggleable: false,
        acrylicDisabled: true,
        size: const NavigationPaneSize(compactWidth: 64),
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.home),
            title: Text(loc.home),
            body: const DashboardPage(),
          ),
        ],
        footerItems: [
          PaneItem(
            icon: const Icon(FluentIcons.settings),
            title: Text(loc.settings),
            body: const SettingsPage(),
          ),
        ],
      ),
    );
  }
}
