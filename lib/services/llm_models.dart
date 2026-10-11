import 'dart:async';
import 'dart:convert';

import 'package:genkit/genkit.dart';
import 'package:genkit_anthropic/genkit_anthropic.dart';
import 'package:genkit_openai/genkit_openai.dart';
import 'package:dio/dio.dart';
import 'package:openai_dart/openai_dart.dart' as sdk;

import '../models/trading_models.dart';
import '../utils/network.dart';
import '../utils/dio_client.dart';

// Configure native models only; the Agent calls Genkit directly.
({Genkit ai, ModelRef model, Object? config, GenerateMiddlewareRef guard})
createLlmModel({
  required LlmSettings settings,
  required String apiKey,
  required DioClient client,
  String? accountId,
}) {
  final provider = settings.provider;
  final endpoint = settings.endpoint.trim().replaceFirst(RegExp(r'/+$'), '');
  final ai = Genkit(
    isDevEnv: false,
    promptDir: null,
    plugins: [
      if (provider == LlmProvider.anthropic)
        anthropic(
          apiKey: apiKey,
          baseUrl: endpoint.replaceFirst(RegExp(r'/v1/messages$'), ''),
          httpClient: client,
        ),
      if (provider == LlmProvider.openAiCompletions)
        openAI(
          apiKey: apiKey,
          baseUrl: endpoint.replaceFirst(RegExp(r'/chat/completions$'), ''),
          httpClient: client,
        ),
    ],
  );
  final ModelRef model;
  if (provider == LlmProvider.anthropic) {
    model = anthropic.model(settings.model.trim());
  } else if (provider == LlmProvider.openAiCompletions) {
    model = openAI.model(settings.model.trim());
  } else {
    defineResponsesModel(
      ai,
      settings: settings,
      apiKey: apiKey,
      httpClient: client,
      accountId: accountId,
    );
    model = modelRef('decma/responses');
  }
  final guard = ai.defineGenerateMiddleware<void>(
    name: 'completed-model',
    create: (_, _) => _CompletedModel(),
  );
  return (
    ai: ai,
    model: model,
    guard: guard(),
    config: provider == LlmProvider.anthropic
        ? AnthropicOptions(maxTokens: 16384)
        : null,
  );
}

// Reject EOF without a finish reason before Genkit executes unfinished tools.
class _CompletedModel extends GenerateMiddleware {
  @override
  Future<ModelResponse> model(
    ModelRequest request,
    ActionFnArg<ModelResponseChunk, ModelRequest, void> ctx,
    Future<ModelResponse> Function(
      ModelRequest,
      ActionFnArg<ModelResponseChunk, ModelRequest, void>,
    )
    next,
  ) async {
    final result = await next(request, ctx);
    if (result.finishReason == FinishReason.unknown) {
      // The OpenAI plugin maps enum.name instead of its snake_case wire value.
      final choices = result.raw?['choices'];
      final reason = choices is List && choices.isNotEmpty
          ? (choices.first as Map)['finish_reason']
          : null;
      if (reason == 'tool_calls') {
        result.finishReason = FinishReason.stop;
        return result;
      }
      if (reason == 'content_filter') {
        result.finishReason = FinishReason.blocked;
        return result;
      }
      throw const AppFailure(
        kind: AppFailureKind.invalidResponse,
        provider: 'LLM',
      );
    }
    return result;
  }
}

// Adapt one Responses call; Genkit alone decides when to execute more turns.
void defineResponsesModel(
  Genkit ai, {
  required LlmSettings settings,
  required String apiKey,
  required DioClient httpClient,
  String? accountId,
}) {
  final codex = settings.provider == LlmProvider.openAiCodex;
  if (codex && (accountId == null || accountId.isEmpty)) {
    throw Exception('OpenAI Codex OAuth 缺少 ChatGPT account ID，请重新登录。');
  }
  final client = sdk.OpenAIClient(
    httpClient: httpClient,
    config: sdk.OpenAIConfig(
      baseUrl: settings.endpoint
          .trim()
          .replaceFirst(RegExp(r'/+$'), '')
          .replaceFirst(RegExp(r'/responses$'), ''),
      authProvider: sdk.ApiKeyProvider(apiKey),
      timeout: const Duration(minutes: 5),
      retryPolicy: const sdk.RetryPolicy(maxRetries: 0),
      defaultHeaders: codex
          ? {
              'ChatGPT-Account-Id': accountId!,
              'OpenAI-Beta': 'responses=experimental',
              'originator': 'codex_cli_rs',
              'Accept': 'text/event-stream',
            }
          : const {},
    ),
  );
  ai.defineModel(
    name: 'decma/responses',
    info: ModelInfo(
      supports: {'multiturn': true, 'tools': true, 'systemRole': true},
    ),
    fn: (request, ctx) async {
      final messages = request.messages;
      final previous = messages.lastIndexWhere(
        (m) => m.role == Role.model && m.metadata?['responseId'] != null,
      );
      final replay = codex || previous < 0
          ? messages
          : messages.skip(previous + 1);
      final input = <Map<String, dynamic>>[];

      // Codex must replay opaque reasoning and all prior output items intact.
      for (final message in replay) {
        if (message.role == Role.system) continue;
        if (message.role == Role.model &&
            message.metadata?['outputItems'] is List) {
          input.addAll(
            List<Map<String, dynamic>>.from(message.metadata!['outputItems']),
          );
        } else if (message.role == Role.tool) {
          for (final part in message.content) {
            final result = part.toolResponsePart?.toolResponse;
            if (result == null) continue;
            input.add({
              'type': 'function_call_output',
              'call_id': result.ref,
              'output': result.output is String
                  ? result.output
                  : jsonEncode(result.output),
            });
          }
        } else {
          input.add({
            'type': 'message',
            'role': message.role == Role.user ? 'user' : 'assistant',
            'content': [
              {
                'type': message.role == Role.user
                    ? 'input_text'
                    : 'output_text',
                'text': message.text,
              },
            ],
          });
        }
      }
      final body = sdk.CreateResponseRequest(
        model: settings.model.trim(),
        instructions: messages
            .where((m) => m.role == Role.system)
            .map((m) => m.text)
            .join('\n'),
        input: sdk.ResponseInput.fromOutputItems(input),
        previousResponseId: !codex && previous >= 0
            ? messages[previous].metadata!['responseId'] as String
            : null,
        store: codex ? false : null,
        tools: [
          for (final tool in request.tools ?? <ToolDefinition>[])
            sdk.ResponseTool.function(
              name: tool.name,
              description: tool.description,
              parameters: tool.inputSchema,
              strict: false,
            ),
        ],
      );

      // The SDK parses SSE; keep done items for gateways with sparse terminals.
      final accumulator = sdk.ResponseStreamAccumulator();
      final doneItems = <int, sdk.OutputItem>{};
      final doneText = <String>[];
      // The supplied HTTP client already aborts requests with the run token.
      await for (final event in client.responses.createStream(body)) {
        ctx.cancel?.throwIfCancelled();
        accumulator.add(event);
        if (event is sdk.OutputItemDoneEvent) {
          doneItems[event.outputIndex] = event.item;
        }
        if (event is sdk.OutputTextDoneEvent) doneText.add(event.text);
        if (event is sdk.OutputTextDeltaEvent && ctx.streamingRequested) {
          ctx.sendChunk(
            ModelResponseChunk(content: [TextPart(text: event.delta)]),
          );
        }
      }
      var response = accumulator.response;
      if (!accumulator.isSuccessful || response == null) {
        throw const AppFailure(
          kind: AppFailureKind.invalidResponse,
          provider: 'LLM',
        );
      }
      // Preserve complete items in their provider order, including reasoning.
      if (response.output.isEmpty && doneItems.isNotEmpty) {
        final indexes = doneItems.keys.toList()..sort();
        response = sdk.Response.fromJson({
          ...response.toJson(),
          'output': indexes.map((i) => doneItems[i]!.toJson()).toList(),
        });
      }
      final text = response.outputText.isNotEmpty
          ? response.outputText
          : doneText.isNotEmpty
          ? doneText.join('\n')
          : accumulator.text;
      final parts = <Part>[
        if (text.isNotEmpty) TextPart(text: text),
        for (final call in response.functionCalls)
          ToolRequestPart(
            toolRequest: ToolRequest(
              ref: call.callId,
              name: call.name,
              input: jsonDecode(call.arguments),
            ),
          ),
      ];
      return ModelResponse(
        finishReason: FinishReason.stop,
        message: Message(
          role: Role.model,
          content: parts,
          metadata: {
            'responseId': response.id,
            'outputItems': response.output
                .map((item) => item.toJson())
                .toList(),
          },
        ),
        raw: response.toJson(),
      );
    },
  );
}

// Keep localized application errors when Genkit returns an abnormal result.
AppFailure llmFailure(Object? cause, String? status) {
  // Streaming plugins may wrap an HTTP failure in multiple Genkit exceptions.
  while (cause is GenkitException && cause.cause != null) {
    cause = cause.cause;
  }
  if (cause is AppFailure) return cause;
  if (cause is DioException) return AppFailure.fromDio(cause, provider: 'LLM');
  if (cause is sdk.ConnectionException) {
    return const AppFailure(
      kind: AppFailureKind.networkUnavailable,
      provider: 'LLM',
    );
  }
  if (cause is TimeoutException || cause is sdk.RequestTimeoutException) {
    return const AppFailure(kind: AppFailureKind.timeout, provider: 'LLM');
  }
  final code = cause is sdk.ApiException ? cause.statusCode : null;
  final kind = switch (code) {
    401 || 403 => AppFailureKind.authentication,
    429 => AppFailureKind.rateLimited,
    408 || 504 => AppFailureKind.timeout,
    final value when value != null && value >= 500 => AppFailureKind.upstream,
    _ => switch (status) {
      'UNAUTHENTICATED' || 'PERMISSION_DENIED' => AppFailureKind.authentication,
      'RESOURCE_EXHAUSTED' => AppFailureKind.rateLimited,
      'DEADLINE_EXCEEDED' => AppFailureKind.timeout,
      'UNAVAILABLE' => AppFailureKind.networkUnavailable,
      _ => AppFailureKind.invalidResponse,
    },
  };
  return AppFailure(kind: kind, provider: 'LLM', statusCode: code);
}
