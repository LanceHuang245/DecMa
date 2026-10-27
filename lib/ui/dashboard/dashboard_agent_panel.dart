import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../domain/models/app_settings.dart';
import '../../domain/models/llm_model_info.dart';
import 'llm_model_selector.dart';
import 'dashboard_messages.dart';
import 'dashboard_controller.dart';
import '../../l10n/generated/app_localizations.dart';

class DashboardAgentPanel extends StatelessWidget {
  const DashboardAgentPanel({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.showScrollToBottom,
    required this.llm,
    required this.modelCatalogKey,
    required this.loadModels,
    required this.onModelChanged,
    required this.onReasoningChanged,
    required this.loading,
    required this.promptController,
    required this.onQuickAnalysis,
    required this.onSend,
    required this.onStop,
    required this.onClear,
    required this.onScrollToBottom,
  });

  final List<DashboardMessage> messages;
  final ScrollController scrollController;
  final bool showScrollToBottom;
  final LlmSettings llm;
  final Key modelCatalogKey;
  final Future<List<LlmModelInfo>> Function(CancelToken) loadModels;
  final Future<void> Function(String) onModelChanged;
  final Future<void> Function(String?) onReasoningChanged;
  final bool loading;
  final TextEditingController promptController;
  // true for swing (days), false for short-term (intraday).
  final ValueChanged<bool> onQuickAnalysis;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onClear;
  final VoidCallback onScrollToBottom;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final resources = FluentTheme.of(context).resources;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Trading Agent',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Card(
                  backgroundColor: resources.subtleFillColorSecondary,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final message in messages) ...[
                          message.isActivity
                              ? ActivityMessage(message)
                              : ConversationMessage(message),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ),
                if (showScrollToBottom)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Tooltip(
                      message: loc.scrollToBottom,
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          icon: const Icon(FluentIcons.chevron_down),
                          onPressed: onScrollToBottom,
                          style: ButtonStyle(
                            backgroundColor: WidgetStatePropertyAll(
                              FluentTheme.of(context).accentColor,
                            ),
                            foregroundColor: const WidgetStatePropertyAll(
                              Colors.white,
                            ),
                            shape: const WidgetStatePropertyAll(CircleBorder()),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          LlmModelSelector(
            key: modelCatalogKey,
            llm: llm,
            loadModels: loadModels,
            onChanged: onModelChanged,
            onReasoningChanged: onReasoningChanged,
            enabled: !loading,
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              TextBox(
                controller: promptController,
                minLines: 3,
                maxLines: 5,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 46),
                placeholder: loc.promptPlaceholder,
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: DropDownButton(
                  disabled: loading,
                  title: Text(loc.analyzeCurrentContract),
                  items: [
                    MenuFlyoutItem(
                      text: Text(loc.shortTermAnalysis),
                      onPressed: () => onQuickAnalysis(false),
                    ),
                    MenuFlyoutItem(
                      text: Text(loc.swingAnalysis),
                      onPressed: () => onQuickAnalysis(true),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  // Keep cancellation available throughout preparation and output.
                  onPressed: loading ? onStop : onSend,
                  child: Text(loading ? loc.stopGenerating : loc.send),
                ),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: loading ? null : onClear,
                child: Text(loc.clear),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
