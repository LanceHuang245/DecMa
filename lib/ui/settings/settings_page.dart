import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_languages.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../providers/app_providers.dart';
import '../theme_mode.dart';
import 'agent_settings_section.dart';
import 'news_settings_section.dart';

// Windows 11 settings list: one card per setting, groups open as expanders.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context);
    final controller = ref.watch(dashboardControllerProvider);
    final settingsStore = ref.read(llmSettingsStoreProvider);
    // Not ScaffoldPage.scrollable: its lazy ListView disposes off-screen cards,
    // collapsing expanders and dropping unsaved drafts.
    return ScaffoldPage(
      header: PageHeader(title: Text(loc.settings)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SettingsCard(
              icon: FluentIcons.locale_language,
              title: loc.language,
              description: loc.languageDescription,
              // Switch the language immediately and remember it for the next launch.
              action: ComboBox<String>(
                value: localeCodeNotifier.value,
                items: [
                  for (final language in appLanguages)
                    ComboBoxItem(
                      value: language.code,
                      child: Text(language.name),
                    ),
                ],
                onChanged: (code) {
                  if (code == null) return;
                  localeCodeNotifier.value = code;
                  unawaited(settingsStore.saveLocaleCode(code));
                },
              ),
            ),
            const SizedBox(height: 5),
            _SettingsCard(
              icon: FluentIcons.color,
              title: loc.theme,
              description: loc.themeDescription,
              // Apply the theme immediately and remember it for the next launch.
              action: ValueListenableBuilder(
                valueListenable: themeModeNotifier,
                builder: (context, mode, _) => ComboBox<ThemeMode>(
                  value: mode,
                  items: [
                    ComboBoxItem(
                      value: ThemeMode.system,
                      child: Text(loc.themeSystem),
                    ),
                    ComboBoxItem(
                      value: ThemeMode.light,
                      child: Text(loc.themeLight),
                    ),
                    ComboBoxItem(
                      value: ThemeMode.dark,
                      child: Text(loc.themeDark),
                    ),
                  ],
                  onChanged: (mode) {
                    themeModeNotifier.value = mode!;
                    unawaited(settingsStore.saveThemeMode(mode.name));
                  },
                ),
              ),
            ),
            const SizedBox(height: 5),
            _SettingsCard(
              icon: FluentIcons.robot,
              title: loc.agentSettings,
              description: loc.agentSettingsDescription,
              content: AgentSettingsSection(
                llm: controller.llm,
                llmConnections: controller.llmConnections,
                mcp: controller.mcp,
                api: controller.api,
                keyStatus: controller.apiKeyStatus,
                nodeAvailable: ref
                    .read(appInitialSettingsProvider)
                    .nodeAvailable,
                onSave: controller.saveSettings,
              ),
            ),
            const SizedBox(height: 5),
            _SettingsCard(
              icon: FluentIcons.news,
              title: loc.newsSettingsTitle,
              description: loc.newsSettingsDescription,
              content: NewsSettingsSection(
                settings: controller.news,
                keyStatus: controller.apiKeyStatus,
                onSave: controller.saveNewsSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// An icon, title and description row with a trailing action, or an expander when it has content.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
    this.content,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;
  final Widget? content;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final header = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.typography.body),
          Text(
            description,
            style: TextStyle(
              fontSize: 11,
              color: theme.resources.textFillColorSecondary,
            ),
          ),
        ],
      ),
    );
    if (content case final content?) {
      return Expander(
        // Expander adds only 10px after leading; pad to the card row's 16px gap.
        leading: Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: Icon(icon, size: 20),
        ),
        header: header,
        content: content,
      );
    }
    return Card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 16),
          Expanded(child: header),
          ?action,
        ],
      ),
    );
  }
}
