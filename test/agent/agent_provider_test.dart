import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent_provider.dart';

void main() {
  test('opencode-go preset uses Go base URL and OPENCODE_API_KEY', () {
    final resolved = resolveAgentRuntime(
      dartDefineProvider: 'opencode-go',
      dartDefineModel: 'kimi-k2.6',
      environment: {'OPENCODE_API_KEY': 'oc-secret'},
    );
    expect(resolved.useFake, isFalse);
    expect(resolved.presetId, 'opencode-go');
    expect(resolved.baseUrl, 'https://opencode.ai/zen/go/v1');
    expect(resolved.apiKey, 'oc-secret');
    expect(resolved.model, 'kimi-k2.6');
    expect(
      agentProviderHeaders(
        presetId: 'opencode-go',
        sessionId: 'agent_1',
      )['x-opencode-session'],
      'agent_1',
    );
  });

  test('openrouter preset uses OpenRouter base URL and OPENROUTER_API_KEY', () {
    final resolved = resolveAgentRuntime(
      dartDefineProvider: 'openrouter',
      dartDefineModel: 'anthropic/claude-sonnet-4',
      environment: {'OPENROUTER_API_KEY': 'or-secret'},
    );
    expect(resolved.useFake, isFalse);
    expect(resolved.presetId, 'openrouter');
    expect(resolved.baseUrl, 'https://openrouter.ai/api/v1');
    expect(resolved.apiKey, 'or-secret');
    expect(
      agentProviderHeaders(presetId: 'openrouter', sessionId: 'x')['X-Title'],
      'Skapie',
    );
  });

  test('SKAPIE_AGENT_API_KEY wins over native env', () {
    final resolved = resolveAgentRuntime(
      dartDefineProvider: 'openai',
      dartDefineApiKey: 'sk-define',
      dartDefineModel: 'gpt-4o-mini',
      environment: {'OPENAI_API_KEY': 'sk-env'},
    );
    expect(resolved.apiKey, 'sk-define');
    expect(resolved.baseUrl, 'https://api.openai.com/v1');
  });

  test('missing key falls back to Fake', () {
    final resolved = resolveAgentRuntime(dartDefineProvider: 'openai');
    expect(resolved.useFake, isTrue);
  });

  test('unset provider infers opencode-go from OPENCODE_API_KEY', () {
    final resolved = resolveAgentRuntime(
      dartDefineModel: 'kimi-k2.6',
      environment: {'OPENCODE_API_KEY': 'oc-secret'},
    );
    expect(resolved.presetId, 'opencode-go');
    expect(resolved.useFake, isFalse);
  });

  test('custom without base URL falls back to Fake', () {
    final resolved = resolveAgentRuntime(
      dartDefineProvider: 'custom',
      dartDefineApiKey: 'k',
      dartDefineModel: 'm',
    );
    expect(resolved.useFake, isTrue);
  });
}
