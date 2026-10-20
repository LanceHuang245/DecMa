import 'dart:convert';

import 'package:decma/domain/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../fixtures/agent_fixtures.dart';
import '../../fixtures/llm_fixtures.dart';

void main() {
  // Exercise real request encoding for each provider, including server defaults.
  for (final provider in LlmProvider.values) {
    for (final effort in [
      null,
      ...provider.standardReasoningEfforts,
      if (provider == LlmProvider.openAiCodex) 'ultra',
    ]) {
      test(
        '$provider sends selected effort $effort on the provider wire',
        () async {
          final requests = <Map<String, dynamic>>[];
          final client = MockClient.streaming((_, bytes) async {
            requests.add(
              jsonDecode(utf8.decode(await bytes.toBytes()))
                  as Map<String, dynamic>,
            );
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  firstTextEvent(provider) + lastTextEvents(provider),
                ),
              ),
              200,
              headers: {'content-type': 'text/event-stream'},
            );
          });
          addTearDown(client.close);
          final initial = testSettings(provider);
          expect(
            await generateReply(
              settings: LlmSettings(
                provider: provider,
                endpoint: initial.endpoint,
                model: initial.model,
                reasoningEffort: effort,
              ),
              client: client,
            ),
            'Hello world',
          );
          final body = requests.single;
          switch (provider) {
            case LlmProvider.anthropic:
              expect((body['output_config'] as Map?)?['effort'], effort);
            case LlmProvider.openAiCompletions:
              expect(body['reasoning_effort'], effort);
            default:
              expect((body['reasoning'] as Map?)?['effort'], effort);
          }
          if (effort == null) {
            expect(body.containsKey('reasoning'), isFalse);
            expect(body.containsKey('reasoning_effort'), isFalse);
          }
        },
      );
    }
  }
}
