import 'dart:async';

import 'package:decma/domain/models/app_settings.dart';
import 'package:decma/data/services/openai_codex_oauth.dart';
import 'package:decma/data/services/storage/secure_key_store.dart';
import 'package:decma/ui/settings/agent_settings_dialog.dart';
import 'package:decma/ui/settings/llm_connection_editor.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:decma/l10n/generated/app_localizations.dart';

void main() {
  // Native editor extraction keeps connection metadata and saved-key placeholders intact.
  testWidgets(
    'connection create/delete and masked credentials retain their contract',
    (tester) async {
      final key = GlobalKey<LlmConnectionEditorState>();
      const initial = LlmSettings(
        id: 'primary',
        name: 'Primary config',
        provider: LlmProvider.anthropic,
        endpoint: 'https://api.anthropic.com',
        model: 'claude-valid',
        reasoningEffort: 'high',
      );
      await tester.pumpWidget(
        FluentApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: LlmConnectionEditor(
            key: key,
            initial: initial,
            connections: LlmConnectionSettings(
              connections: const [initial],
              activeConnectionId: 'primary',
            ),
            keys: const ApiKeyStatus(llmKeyConnectionIds: {'primary'}),
          ),
        ),
      );
      expect(key.currentState!.readSettings().apiKey, isNull);
      expect(
        key.currentState!.readSettings().connections.active.reasoningEffort,
        'high',
      );
      expect(
        key.currentState!.readSettings().connections.active.model,
        'claude-valid',
      );
      await tester.tap(find.text('新建配置'));
      await tester.pumpAndSettle();
      final added = key.currentState!.readSettings().connections;
      expect(added.connections, hasLength(2));
      expect(added.active.provider, LlmProvider.openAiResponses);
      expect(added.active.model, 'gpt-4.1');
      await tester.tap(find.text('删除配置'));
      await tester.pumpAndSettle();
      expect(key.currentState!.readSettings().connections.active.id, 'primary');
      expect(key.currentState!.readSettings().apiKey, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  // A login response for a removed editor must not change the new connection.
  testWidgets('late Codex login does not overwrite another connection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    final auth = _Auth();
    const codex = LlmSettings(
      id: 'codex',
      name: 'Codex config',
      provider: LlmProvider.openAiCodex,
      endpoint: 'https://chatgpt.com/backend-api/codex',
      model: 'codex-old',
    );
    const anthropic = LlmSettings(
      id: 'anthropic',
      name: 'Anthropic config',
      provider: LlmProvider.anthropic,
      endpoint: 'https://api.anthropic.com',
      model: 'claude-valid',
    );
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: AgentSettingsDialog(
          llm: codex,
          llmConnections: LlmConnectionSettings(
            connections: const [codex, anthropic],
            activeConnectionId: 'codex',
          ),
          mcp: const McpSettings(
            useBybit: false,
            useNansen: false,
            useOpenWebSearch: false,
          ),
          api: const ApiSettings(useCoinalyze: false),
          keyStatus: const ApiKeyStatus(hasCodexOAuth: true),
          nodeAvailable: false,
          codexAuth: auth,
          onSave: (_, _, _, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新登录'));
    await tester.pump();
    await tester.tap(find.text('Codex config').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anthropic config').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .state<LlmConnectionEditorState>(find.byType(LlmConnectionEditor))
          .readSettings()
          .connections
          .active
          .model,
      'claude-valid',
    );
    auth.models.complete(['codex-new']);
    await tester.pumpAndSettle();
    expect(
      tester
          .state<LlmConnectionEditorState>(find.byType(LlmConnectionEditor))
          .readSettings()
          .connections
          .active
          .model,
      'claude-valid',
    );
    expect(find.text('codex-new'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}

// Replace only the remote model catalog so the real connection editor runs.
class _Auth extends OpenAiCodexAuthService {
  final models = Completer<List<String>>();
  @override
  Future<List<String>> signIn({CancelToken? cancelToken}) => models.future;
}
