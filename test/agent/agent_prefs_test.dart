import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent_prefs.dart';

void main() {
  test(
    'prefs JSON round-trips provider, model, and base URL without a key',
    () {
      const prefs = AgentPrefs(
        providerId: 'opencode-go',
        model: 'kimi-k2.6',
        baseUrl: 'https://example.test/v1',
      );
      final json = prefs.toJson();
      expect(json.containsKey('apiKey'), isFalse);
      expect(json.containsKey('api_key'), isFalse);
      expect(json['provider'], 'opencode-go');
      expect(json['model'], 'kimi-k2.6');
      expect(json['baseUrl'], 'https://example.test/v1');

      final loaded = AgentPrefs.fromJson(json);
      expect(loaded.providerId, prefs.providerId);
      expect(loaded.model, prefs.model);
      expect(loaded.baseUrl, prefs.baseUrl);
    },
  );

  test('fromJson ignores an apiKey if a file ever contained one', () {
    final loaded = AgentPrefs.fromJson({
      'provider': 'openai',
      'model': 'gpt-4o-mini',
      'apiKey': 'sk-should-not-load',
    });
    expect(loaded.providerId, 'openai');
    expect(loaded.model, 'gpt-4o-mini');
    expect(jsonEncode(loaded.toJson()), isNot(contains('sk-should-not-load')));
  });

  test('prefs file save then load does not write a key', () async {
    final dir = await Directory.systemTemp.createTemp('skapie_agent_prefs_');
    addTearDown(() => dir.delete(recursive: true));
    final file = agentPrefsFile(dir);
    final store = AgentPrefsStore(file);

    await store.save(
      const AgentPrefs(
        providerId: 'openrouter',
        model: 'anthropic/claude-sonnet-4',
      ),
    );
    final text = file.readAsStringSync();
    expect(text.toLowerCase(), isNot(contains('apikey')));
    expect(text, isNot(contains('sk-')));

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.providerId, 'openrouter');
    expect(loaded.model, 'anthropic/claude-sonnet-4');
    expect(loaded.baseUrl, isNull);
  });

  test('missing prefs file loads as null', () async {
    final dir = await Directory.systemTemp.createTemp('skapie_agent_prefs_');
    addTearDown(() => dir.delete(recursive: true));
    final loaded = await AgentPrefsStore(agentPrefsFile(dir)).load();
    expect(loaded, isNull);
  });
}
