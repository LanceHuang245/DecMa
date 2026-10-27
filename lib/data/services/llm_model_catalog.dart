import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/models/app_settings.dart';
import '../../domain/models/llm_model_info.dart';
import '../../utils/network.dart';
import 'openai_codex_oauth.dart';
import 'storage/secure_key_store.dart';

// Read each catalog using the same connection and credentials as generation.
Future<List<LlmModelInfo>> fetchLlmModels(
  LlmSettings settings, {
  required SecureKeyStore keys,
  required CancelToken cancelToken,
  Dio? dio,
  OpenAiCodexAuthService? codexAuth,
}) async {
  if (settings.provider == LlmProvider.openAiCodex) {
    final auth = codexAuth ?? OpenAiCodexAuthService(keyStore: keys);
    try {
      return await auth.fetchModelCatalog(cancelToken: cancelToken);
    } finally {
      if (codexAuth == null) auth.dispose();
    }
  }
  final client = dio ?? createDio();
  try {
    final key = await keys.readLlmKey(connectionId: settings.id);
    if (cancelToken.isCancelled) {
      throw const AppFailure(kind: AppFailureKind.cancelled);
    }
    final anthropic = settings.provider == LlmProvider.anthropic;
    var endpoint = settings.endpoint.trim().replaceFirst(RegExp(r'/+$'), '');
    endpoint = endpoint.replaceFirst(
      RegExp(r'/(responses|chat/completions|messages)$'),
      '',
    );
    if (anthropic && !endpoint.endsWith('/v1')) endpoint = '$endpoint/v1';
    final models = <String, LlmModelInfo>{};
    String? after;
    // Anthropic catalogs are paginated; OpenAI returns a single data array.
    do {
      final response = await runNetworkRequest(
        settings.name,
        () => client.get<String>(
          '$endpoint/models',
          queryParameters: anthropic
              ? {'limit': 1000, 'after_id': ?after}
              : null,
          cancelToken: cancelToken,
          options: networkOptions(
            headers: anthropic
                ? {'x-api-key': key ?? '', 'anthropic-version': '2023-06-01'}
                : {if (key != null) 'Authorization': 'Bearer $key'},
          ),
        ),
      );
      requireSuccessfulResponse(response, provider: settings.name);
      final body = jsonDecode(response.data!) as Map<String, dynamic>;
      for (final item in body['data']) {
        final model = LlmModelInfo.fromJson(item);
        models[model.id] = model;
      }
      after = anthropic && body['has_more'] ? body['last_id'] : null;
    } while (after != null);
    return models.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  } finally {
    if (dio == null) client.close(force: true);
  }
}
