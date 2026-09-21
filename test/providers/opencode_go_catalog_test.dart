import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/providers/model_surface.dart';
import 'package:skapie/providers/opencode_go/opencode_go_catalog.dart';

void main() {
  test('catalog JSON parses ids, surfaces, and default show', () {
    final models = parseOpenCodeGoCatalog(
      jsonDecode('''
{
  "provider": "opencode-go",
  "baseUrl": "https://opencode.ai/zen/go/v1",
  "models": [
    {"id": "deepseek-v4-flash", "surface": "openai-completions"},
    {"id": "gpt-5.6-luna", "surface": "openai-responses", "displayName": "Luna"},
    {"id": "minimax-m3", "surface": "anthropic-messages", "show": false}
  ]
}
'''),
    );
    expect(models, hasLength(3));
    expect(models[0].id, 'deepseek-v4-flash');
    expect(models[0].surface, ModelSurface.completions);
    expect(models[0].show, isTrue);
    expect(models[0].vanillaOk, isTrue);
    expect(models[1].surface, ModelSurface.responses);
    expect(models[1].displayName, 'Luna');
    expect(models[2].surface, ModelSurface.messages);
    expect(models[2].show, isFalse);
  });

  test('shipped catalog file matches the embedded copy', () {
    final file = File(opencodeGoCatalogAsset);
    expect(file.existsSync(), isTrue);
    final fromFile = parseOpenCodeGoCatalog(
      jsonDecode(file.readAsStringSync()),
    );
    final fromEmbed = parseOpenCodeGoCatalog(jsonDecode(opencodeGoCatalogJson));
    expect(fromFile.map(_row), fromEmbed.map(_row));
    expect(opencodeGoCatalog.map(_row), fromFile.map(_row));
  });

  test('shipped OpenCode Go chart covers first-contact surfaces', () {
    expect(
      lookupOpenCodeGoModel('deepseek-v4-flash')?.surface,
      ModelSurface.completions,
    );
    expect(
      lookupOpenCodeGoModel('gpt-5.6-luna')?.surface,
      ModelSurface.responses,
    );
    expect(lookupOpenCodeGoModel('grok-4.6')?.surface, ModelSurface.responses);
    expect(lookupOpenCodeGoModel('minimax-m3')?.surface, ModelSurface.messages);
    expect(
      lookupOpenCodeGoModel('qwen3.8-flash')?.surface,
      ModelSurface.messages,
    );
    expect(lookupOpenCodeGoModel('unknown-live-id'), isNull);
  });

  test('unknown surface throws', () {
    expect(
      () => parseOpenCodeGoCatalog({
        'models': [
          {'id': 'x', 'surface': 'soap'},
        ],
      }),
      throwsA(isA<FormatException>()),
    );
  });
}

String _row(dynamic model) {
  return '${model.id}|${model.surface.id}|${model.displayName}|${model.show}|${model.vanillaOk}';
}
