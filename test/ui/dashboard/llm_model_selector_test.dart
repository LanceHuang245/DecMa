import 'dart:async';

import 'package:decma/domain/models/app_settings.dart';
import 'package:decma/domain/models/llm_model_info.dart';
import 'package:decma/ui/dashboard/llm_model_selector.dart';
import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _first = LlmSettings(
  id: 'first',
  name: 'First config',
  provider: LlmProvider.openAiResponses,
  endpoint: 'https://llm.test/v1',
  model: 'saved',
);
const _second = LlmSettings(
  id: 'second',
  name: 'Second config',
  provider: LlmProvider.anthropic,
  endpoint: 'https://other.test',
  model: 'other-saved',
);

void main() {
  // Removed choices must stay hidden even when saved or advertised remotely.
  for (final saved in ['', 'default', 'none', 'minimal']) {
    testWidgets('removed effort $saved cannot reappear from saved settings', (
      tester,
    ) async {
      await tester.pumpWidget(
        FluentApp(
          home: Center(
            child: SizedBox(
              width: 320,
              child: LlmModelSelector(
                llm: LlmSettings(
                  provider: LlmProvider.openAiCodex,
                  endpoint: 'https://llm.test',
                  model: 'saved',
                  reasoningEffort: saved,
                ),
                loadModels: (_) async => const [
                  LlmModelInfo(
                    'saved',
                    reasoningEfforts: [
                      '',
                      'default',
                      'none',
                      'minimal',
                      'low',
                      'high',
                    ],
                  ),
                ],
                onChanged: (_) async {},
                onReasoningChanged: (_) async {},
                enabled: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final combo = tester.widget<ComboBox<String>>(
        find.byType(ComboBox<String>).last,
      );
      expect(combo.value, isNull);
      expect(combo.items!.map((item) => item.value), ['low', 'high']);
      expect(find.text('思考等级'), findsOneWidget);
      for (final label in ['默认', '关闭', '最低']) {
        expect(find.text(label), findsNothing);
      }
    });
  }

  // Compatible gateways can use protocol choices without advertising metadata.
  for (final provider in LlmProvider.values) {
    testWidgets('$provider falls back to standard reasoning levels', (
      tester,
    ) async {
      String? selected;
      await tester.pumpWidget(
        FluentApp(
          home: Center(
            child: SizedBox(
              width: 320,
              child: LlmModelSelector(
                llm: LlmSettings(
                  provider: provider,
                  endpoint: 'https://third-party.test/v1',
                  model: 'third-party-model',
                ),
                loadModels: (_) async => const [
                  LlmModelInfo('third-party-model'),
                ],
                onChanged: (_) async {},
                onReasoningChanged: (effort) async => selected = effort,
                enabled: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final combo = tester.widget<ComboBox<String>>(
        find.byType(ComboBox<String>).last,
      );
      expect(combo.items!.map((item) => item.value), [
        ...provider.standardReasoningEfforts,
      ]);
      expect(combo.onChanged, isNotNull);
      await tester.tap(find.byType(ComboBox<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('极高').last);
      await tester.pumpAndSettle();
      expect(selected, 'xhigh');
    });
  }

  // Effort choices come from the selected model rather than a global preset list.
  testWidgets(
    'reasoning picker uses model metadata to the right of the model',
    (tester) async {
      String? selected;
      Widget view(LlmSettings llm) => FluentApp(
        home: Center(
          child: SizedBox(
            width: 320,
            child: LlmModelSelector(
              llm: llm,
              loadModels: (_) async => const [
                LlmModelInfo(
                  'saved',
                  reasoningEfforts: ['low', 'ultra', 'custom'],
                ),
                LlmModelInfo('other-model', reasoningEfforts: []),
              ],
              onChanged: (_) async {},
              onReasoningChanged: (effort) async => selected = effort,
              enabled: true,
            ),
          ),
        ),
      );
      await tester.pumpWidget(view(_first));
      await tester.pumpAndSettle();
      final combos = find.byType(ComboBox<String>);
      expect(
        tester.getTopLeft(combos.last).dx,
        greaterThan(tester.getTopRight(combos.first).dx),
      );
      expect(
        tester
            .widget<ComboBox<String>>(combos.last)
            .items!
            .map((item) => item.value),
        ['low', 'ultra', 'custom'],
      );
      expect(
        tester
            .widget<ComboBox<String>>(combos.last)
            .items!
            .map((item) => (item.child as Text).data),
        ['低', '极致', 'custom'],
      );
      await tester.tap(find.byType(ComboBox<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('极致').last);
      await tester.pumpAndSettle();
      expect(selected, 'ultra');
      await tester.pumpWidget(
        view(
          const LlmSettings(
            id: 'first',
            name: 'First config',
            provider: LlmProvider.openAiResponses,
            endpoint: 'https://llm.test/v1',
            model: 'other-model',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<ComboBox<String>>(combos.last).onChanged, isNull);
      expect(
        tester
            .widget<ComboBox<String>>(combos.last)
            .items!
            .map((item) => item.value),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  // Switching configurations cancels old catalogs without changing saved models.
  testWidgets('a stale catalog cannot replace the current connection', (
    tester,
  ) async {
    final old = Completer<List<LlmModelInfo>>();
    CancelToken? oldCancel;
    Widget view(
      LlmSettings llm,
      Future<List<LlmModelInfo>> Function(CancelToken) load,
    ) => FluentApp(
      home: Center(
        child: SizedBox(
          width: 320,
          child: LlmModelSelector(
            llm: llm,
            loadModels: load,
            onChanged: (_) async {},
            onReasoningChanged: (_) async {},
            enabled: true,
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      view(_first, (cancel) {
        oldCancel = cancel;
        return old.future;
      }),
    );
    await tester.pumpWidget(
      view(_second, (_) async => [const LlmModelInfo('new-model')]),
    );
    await tester.pumpAndSettle();
    expect(oldCancel!.isCancelled, isTrue);
    old.complete([const LlmModelInfo('stale-model')]);
    await tester.pumpAndSettle();
    final combo = tester.widget<ComboBox<String>>(
      find.byType(ComboBox<String>).first,
    );
    expect(combo.items!.map((item) => item.value), [
      'new-model',
      'other-saved',
    ]);
    expect(combo.value, 'other-saved');
    expect(find.text('Second config'), findsOneWidget);
    expect(find.text('Anthropic Messages'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // A failed catalog keeps selection usable, and refresh retries the request.
  testWidgets(
    'catalog failure retains the model and refresh allows selection',
    (tester) async {
      var attempts = 0;
      String? selected;
      await tester.pumpWidget(
        FluentApp(
          home: Center(
            child: SizedBox(
              width: 320,
              child: LlmModelSelector(
                llm: _first,
                loadModels: (_) async {
                  if (++attempts == 1) throw Exception('offline');
                  return [const LlmModelInfo('available')];
                },
                onChanged: (model) async => selected = model,
                onReasoningChanged: (_) async {},
                enabled: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('模型列表获取失败'), findsOneWidget);
      expect(
        tester
            .widget<ComboBox<String>>(find.byType(ComboBox<String>).first)
            .value,
        'saved',
      );
      await tester.tap(find.byIcon(FluentIcons.refresh));
      await tester.pumpAndSettle();
      expect(find.textContaining('模型列表获取失败'), findsNothing);
      await tester.tap(find.text('saved'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('available').last);
      await tester.pumpAndSettle();
      expect(selected, 'available');
      expect(attempts, 2);
    },
  );
}
