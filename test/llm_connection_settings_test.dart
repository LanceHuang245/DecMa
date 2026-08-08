import 'package:decma/models/trading_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LLM connection metadata preserves its saved configuration name', () {
    const connection = LlmSettings(
      id: 'work-openai',
      name: '工作 OpenAI',
      provider: LlmProvider.openAiResponses,
      endpoint: 'https://api.openai.com/v1',
      model: 'gpt-5.6-sol',
    );

    expect(LlmSettings.fromJson(connection.toJson())?.name, '工作 OpenAI');
    expect(LlmSettings.fromJson(connection.toJson())?.id, 'work-openai');
  });

  test('active connection falls back to the first saved connection', () {
    const first = LlmSettings(
      id: 'first',
      name: 'First',
      provider: LlmProvider.openAiResponses,
      endpoint: 'https://api.openai.com/v1',
      model: 'gpt-4.1',
    );
    const second = LlmSettings(
      id: 'second',
      name: 'Second',
      provider: LlmProvider.anthropic,
      endpoint: 'https://api.anthropic.com',
      model: 'claude-sonnet-4-5',
    );

    final settings = LlmConnectionSettings(
      connections: [first, second],
      activeConnectionId: 'missing',
    );

    expect(settings.active.id, first.id);
  });
}
