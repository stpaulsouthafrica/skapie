import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/agent_prefs.dart';

void main() {
  test('prefs JSON round-trips provider, model, thinkingLevel, and key', () {
    const prefs = AgentPrefs(
      providerId: 'openrouter',
      model: 'anthropic/claude-sonnet-4',
      thinkingLevel: 'high',
      apiKey: 'or-local',
    );
    final json = prefs.toJson();
    expect(json.containsKey('baseUrl'), isFalse);
    expect(json['provider'], 'openrouter');
    expect(json['model'], 'anthropic/claude-sonnet-4');
    expect(json['thinkingLevel'], 'high');
    expect(json['apiKey'], 'or-local');

    final loaded = AgentPrefs.fromJson(json);
    expect(loaded.providerId, prefs.providerId);
    expect(loaded.model, prefs.model);
    expect(loaded.thinkingLevel, 'high');
    expect(loaded.apiKey, 'or-local');
    expect(loaded.sendKitTools, isTrue);
  });

  test('fromJson without apiKey still loads provider and model', () {
    final loaded = AgentPrefs.fromJson({
      'provider': 'openai',
      'model': 'gpt-4o-mini',
    });
    expect(loaded.providerId, 'openai');
    expect(loaded.model, 'gpt-4o-mini');
    expect(loaded.apiKey, isNull);
  });

  test('prefs file save then load keeps key and omits baseUrl', () async {
    final dir = await Directory.systemTemp.createTemp('skapie_agent_prefs_');
    addTearDown(() => dir.delete(recursive: true));
    final file = agentPrefsFile(dir);
    final store = AgentPrefsStore(file);

    await store.save(
      const AgentPrefs(
        providerId: 'openrouter',
        model: 'anthropic/claude-sonnet-4',
        thinkingLevel: 'medium',
        apiKey: 'or-local',
      ),
    );
    final text = file.readAsStringSync();
    expect(text, contains('or-local'));
    expect(text.contains('baseUrl'), isFalse);
    expect(text, isNot(contains('scene')));

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.providerId, 'openrouter');
    expect(loaded.model, 'anthropic/claude-sonnet-4');
    expect(loaded.thinkingLevel, 'medium');
    expect(loaded.apiKey, 'or-local');
  });

  test('prefs file save then load keeps sendKitTools false', () async {
    final dir = await Directory.systemTemp.createTemp('skapie_agent_prefs_');
    addTearDown(() => dir.delete(recursive: true));
    final store = AgentPrefsStore(agentPrefsFile(dir));
    await store.save(
      const AgentPrefs(
        providerId: 'opencode-go',
        model: 'kimi-k2.6',
        apiKey: 'oc-local',
        sendKitTools: false,
      ),
    );
    final loaded = await store.load();
    expect(loaded!.sendKitTools, isFalse);
    expect(loaded.apiKey, 'oc-local');
    expect(loaded.model, 'kimi-k2.6');
  });

  test('missing prefs file loads as null', () async {
    final dir = await Directory.systemTemp.createTemp('skapie_agent_prefs_');
    addTearDown(() => dir.delete(recursive: true));
    final loaded = await AgentPrefsStore(agentPrefsFile(dir)).load();
    expect(loaded, isNull);
  });
}
