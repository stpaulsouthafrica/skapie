import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent.dart';
import 'package:skapie/agent/conversation_turn.dart';
import 'package:skapie/agent/llm_request_preview.dart';
import 'package:skapie/agent/openai_compatible.dart';

void main() {
  test('fake run shows the echo payload and no web request', () {
    final text = formatLlmRequestPreview(
      prompt: 'hello from the card',
      useFake: true,
      sessionModel: const FakeAgentModel(),
      attachedTools: const [],
      presetId: 'fake',
      baseUrl: null,
      apiKey: null,
      runtimeModel: null,
      kitModel: '',
      kitProvider: '',
      sessionId: 's1',
    );
    expect(text, contains('No network request'));
    expect(text, contains('hello from the card'));
    expect(text, isNot(contains('POST ')));
  });

  test('vanilla preview is the completions body and hides the key', () {
    final text = formatLlmRequestPreview(
      prompt: 'hello from the card',
      useFake: false,
      sessionModel: const FakeAgentModel(),
      attachedTools: const [],
      presetId: 'opencode-go',
      baseUrl: 'https://opencode.ai/zen/go/v1',
      apiKey: 'oc-secret',
      runtimeModel: 'deepseek-v4-flash',
      kitModel: 'deepseek-v4-flash',
      kitProvider: 'opencode-go',
      sessionId: 's1',
    );
    expect(
      text,
      contains('POST https://opencode.ai/zen/go/v1/chat/completions'),
    );
    expect(text, contains('hello from the card'));
    expect(text, contains('"model": "deepseek-v4-flash"'));
    expect(text, contains('"role": "user"'));
    expect(text, isNot(contains('oc-secret')));
    expect(text, contains('Authorization: <redacted>'));
  });

  test('attached tools preview the first chat completion', () {
    final model = OpenAiCompatibleAgentModel(
      baseUrl: 'https://example.test/v1',
      apiKey: 'sk-live',
      model: 'demo',
      headers: const {'X-Title': 'Skapie'},
    );
    final text = formatLlmRequestPreview(
      prompt: 'use the tool',
      useFake: false,
      sessionModel: model,
      attachedTools: [
        AgentTool(
          name: 'list_kits',
          description: 'List registered kits.',
          run: (_) async => <String, Object?>{},
        ),
      ],
      presetId: 'openai',
      baseUrl: 'https://example.test/v1',
      apiKey: 'sk-live',
      runtimeModel: 'demo',
      kitModel: 'other-model',
      kitProvider: '',
      sessionId: 's1',
    );
    expect(text, contains('POST https://example.test/v1/chat/completions'));
    expect(text, contains('"role": "system"'));
    expect(text, contains('use the tool'));
    expect(text, contains('list_kits'));
    expect(text, contains('"model": "demo"'));
    expect(text, isNot(contains('other-model')));
    expect(text, isNot(contains('sk-live')));
    expect(text, contains('X-Title: Skapie'));
  });

  test('preview puts context first and keeps conversation roles', () {
    final text = formatLlmRequestPreview(
      prompt: 'again',
      systemText: 'Texting from space',
      history: const [
        ConversationTurn(role: 'user', content: 'hello'),
        ConversationTurn(role: 'assistant', content: 'reply 1'),
      ],
      useFake: false,
      sessionModel: const FakeAgentModel(),
      attachedTools: const [],
      presetId: 'opencode-go',
      baseUrl: 'https://opencode.ai/zen/go/v1',
      apiKey: 'oc-secret',
      runtimeModel: 'deepseek-v4-flash',
      kitModel: 'deepseek-v4-flash',
      kitProvider: 'opencode-go',
      sessionId: 's1',
    );
    final systemAt = text.indexOf('"role": "system"');
    final firstUser = text.indexOf('"content": "hello"');
    final assistant = text.indexOf('"content": "reply 1"');
    final again = text.indexOf('"content": "again"');
    expect(systemAt, greaterThanOrEqualTo(0));
    expect(systemAt, lessThan(firstUser));
    expect(firstUser, lessThan(assistant));
    expect(assistant, lessThan(again));
    expect(text, contains('Texting from space'));
  });
}
