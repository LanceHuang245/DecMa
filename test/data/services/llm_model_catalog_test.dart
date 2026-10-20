import 'dart:convert';

import 'package:decma/data/services/llm_model_catalog.dart';
import 'package:decma/data/services/openai_codex_oauth.dart';
import 'package:decma/data/services/storage/secure_key_store.dart';
import 'package:decma/domain/models/app_settings.dart';
import 'package:decma/domain/models/llm_model_info.dart';
import 'package:decma/utils/network.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Full generation URLs and API roots must resolve to the same model catalog.
  for (final entry in [
    (LlmProvider.openAiResponses, 'https://llm.test/v1'),
    (LlmProvider.openAiResponses, 'https://llm.test/v1/responses/'),
    (LlmProvider.openAiCompletions, 'https://llm.test/v1/chat/completions'),
    (LlmProvider.anthropic, 'https://llm.test'),
    (LlmProvider.anthropic, 'https://llm.test/v1/messages'),
  ]) {
    test(
      'catalog uses connection credentials for ${entry.$1} ${entry.$2}',
      () async {
        final keys = _Keys();
        final dio = Dio();
        addTearDown(dio.close);
        final requests = <RequestOptions>[];
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests.add(options);
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: jsonEncode({
                    'data': [
                      {'id': 'model-b'},
                      {
                        'id': 'model-a',
                        if (entry.$1 == LlmProvider.anthropic)
                          'capabilities': {
                            'effort': {
                              'supported': true,
                              'low': {'supported': true},
                              'high': {'supported': true},
                              'max': {'supported': false},
                            },
                          },
                      },
                      {'id': 'model-b'},
                    ],
                    if (entry.$1 == LlmProvider.anthropic) ...{
                      'has_more': requests.length == 1,
                      'last_id': 'model-b',
                    },
                  }),
                ),
              );
            },
          ),
        );
        final models = await fetchLlmModels(
          LlmSettings(
            id: 'custom',
            provider: entry.$1,
            endpoint: entry.$2,
            model: 'saved',
          ),
          keys: keys,
          cancelToken: CancelToken(),
          dio: dio,
        );
        expect(models.map((model) => model.id), ['model-a', 'model-b']);
        expect(
          models.first.reasoningEfforts,
          entry.$1 == LlmProvider.anthropic ? ['low', 'high'] : isNull,
        );
        expect(keys.connectionId, 'custom');
        expect(
          '${requests.first.uri.origin}${requests.first.uri.path}',
          'https://llm.test/v1/models',
        );
        if (entry.$1 == LlmProvider.anthropic) {
          expect(requests.first.headers['x-api-key'], 'custom-key');
          expect(requests.first.headers['anthropic-version'], '2023-06-01');
          expect(requests, hasLength(2));
          expect(requests.last.queryParameters['after_id'], 'model-b');
        } else {
          expect(requests.single.headers['Authorization'], 'Bearer custom-key');
        }
      },
    );
  }

  test(
    'Codex delegates to the existing OAuth catalog with cancellation',
    () async {
      final auth = _Auth();
      addTearDown(auth.dispose);
      final cancel = CancelToken();
      expect(
        (await fetchLlmModels(
          const LlmSettings(
            provider: LlmProvider.openAiCodex,
            endpoint: '',
            model: '',
          ),
          keys: _Keys(),
          cancelToken: cancel,
          codexAuth: auth,
        )).map((model) => model.id),
        ['codex-model'],
      );
      expect(auth.cancel, same(cancel));
    },
  );

  // Verify the actual OAuth catalog response retains dynamic reasoning levels.
  test('Codex catalog preserves advertised efforts beyond SDK enums', () async {
    final dio = Dio();
    addTearDown(dio.close);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.headers['Authorization'], 'Bearer oauth-token');
          expect(options.headers['ChatGPT-Account-Id'], 'account');
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: jsonEncode({
                'models': [
                  {
                    'slug': 'codex-model',
                    'supported_reasoning_levels': [
                      {'effort': 'low', 'description': 'Fast'},
                      {'effort': 'ultra', 'description': 'Deep'},
                    ],
                  },
                ],
              }),
            ),
          );
        },
      ),
    );
    final auth = OpenAiCodexAuthService(keyStore: _Keys(), dio: dio);
    addTearDown(auth.dispose);
    final models = await auth.fetchModelCatalog();
    expect(models.single.id, 'codex-model');
    expect(models.single.reasoningEfforts, ['low', 'ultra']);
  });

  test('catalog authentication failures remain actionable', () async {
    final dio = Dio();
    addTearDown(dio.close);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(requestOptions: options, statusCode: 401, data: '{}'),
          );
        },
      ),
    );
    await expectLater(
      fetchLlmModels(
        const LlmSettings(
          provider: LlmProvider.openAiResponses,
          endpoint: 'https://llm.test/v1',
          model: 'saved',
        ),
        keys: _Keys(),
        cancelToken: CancelToken(),
        dio: dio,
      ),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.kind,
          'kind',
          AppFailureKind.authentication,
        ),
      ),
    );
  });
}

// Keep real request construction while isolating secure storage and OAuth I/O.
class _Keys extends SecureKeyStore {
  String? connectionId;
  @override
  Future<String?> readLlmKey({
    String connectionId = LlmSettings.defaultId,
  }) async {
    this.connectionId = connectionId;
    return 'custom-key';
  }

  @override
  Future<CodexOAuthCredentials?> readCodexOAuth() async =>
      CodexOAuthCredentials(
        accessToken: 'oauth-token',
        refreshToken: 'refresh',
        accountId: 'account',
        expiresAt: DateTime.utc(2099),
      );
}

class _Auth extends OpenAiCodexAuthService {
  CancelToken? cancel;
  @override
  Future<List<LlmModelInfo>> fetchModelCatalog({
    CancelToken? cancelToken,
  }) async {
    cancel = cancelToken;
    return [const LlmModelInfo('codex-model')];
  }
}
