import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent_prefs.dart';

void main() {
  test(
    'prefs JSON round-trips provider, model, thinkingLevel without a key',
    () {
      const prefs = AgentPrefs(
        providerId: 'openrouter',
        model: 'anthropic/claude-sonnet-4',
        thinkingLevel: 'high',
      );
      final json = prefs.toJson();
      expect(json.containsKey('apiKey'), isFalse);
      expect(json.containsKey('api_key'), isFalse);
      expect(json.containsKey('baseUrl'), isFalse);
      expect(json['provider'], 'openrouter');
      expect(json['model'], 'anthropic/claude-sonnet-4');
      expect(json['thinkingLevel'], 'high');

      final loaded = AgentPrefs.fromJson(json);
      expect(loaded.providerId, prefs.providerId);
      expect(loaded.model, prefs.model);
      expect(loaded.thinkingLevel, 'high');
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

  test('prefs file save then load does not write a key or baseUrl', () async {
    final dir = await Directory.systemTemp.createTemp('skapie_agent_prefs_');
    addTearDown(() => dir.delete(recursive: true));
    final file = agentPrefsFile(dir);
    final store = AgentPrefsStore(file);

    await store.save(
      const AgentPrefs(
        providerId: 'openrouter',
        model: 'anthropic/claude-sonnet-4',
        thinkingLevel: 'medium',
      ),
    );
    final text = file.readAsStringSync();
    expect(text.toLowerCase(), isNot(contains('apikey')));
    expect(text, isNot(contains('sk-')));
    expect(text.contains('baseUrl'), isFalse);

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.providerId, 'openrouter');
    expect(loaded.model, 'anthropic/claude-sonnet-4');
    expect(loaded.thinkingLevel, 'medium');
  });

  test('missing prefs file loads as null', () async {
    final dir = await Directory.systemTemp.createTemp('skapie_agent_prefs_');
    addTearDown(() => dir.delete(recursive: true));
    final loaded = await AgentPrefsStore(agentPrefsFile(dir)).load();
    expect(loaded, isNull);
  });
}
