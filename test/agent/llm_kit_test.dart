import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

void main() {
  late KitApi kitApi;

  setUp(() {
    kitApi = createAppKitApi(store: SceneStore());
  });

  test('new LLM kit body already shows Input and Output regions', () {
    final ids = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final body = kitApi.store.document.objectById(ids.last)!;
    expect(body.props['content'], llmKitEmptyContent);
    expect(body.props['prompt'], '');
    expect(body.props['reply'], '');
  });

  test('llmKitBodyForSelection maps frame or body to the compound body', () {
    final first = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final second = kitApi.instantiate(
      harnessLlmKitId,
      origin: const Offset(400, 0),
    );
    final firstFrame = kitApi.store.document.objectById(first.first)!;
    final firstBody = kitApi.store.document.objectById(first.last)!;
    final secondBody = kitApi.store.document.objectById(second.last)!;

    expect(
      llmKitBodyForSelection(
        document: kitApi.store.document,
        selectedId: firstBody.id,
      )?.id,
      firstBody.id,
    );
    expect(
      llmKitBodyForSelection(
        document: kitApi.store.document,
        selectedId: firstFrame.id,
      )?.id,
      firstBody.id,
    );
    expect(
      llmKitBodyForSelection(
        document: kitApi.store.document,
        selectedId: secondBody.id,
      )?.id,
      secondBody.id,
    );
    expect(
      llmKitBodyForSelection(document: kitApi.store.document, selectedId: null),
      isNull,
    );
  });

  test('publishLlmKit updates the targeted body only', () {
    final first = kitApi.instantiate(harnessLlmKitId, origin: Offset.zero);
    final second = kitApi.instantiate(
      harnessLlmKitId,
      origin: const Offset(400, 0),
    );
    publishLlmKit(
      kitApi: kitApi,
      bodyId: second.last,
      prompt: 'targeted',
      reply: 'ok',
    );
    expect(kitApi.store.document.objectById(first.last)!.props['prompt'], '');
    expect(
      kitApi.store.document.objectById(second.last)!.props['prompt'],
      'targeted',
    );
    expect(kitApi.store.document.objectById(second.last)!.props['reply'], 'ok');
    expect(
      kitApi.store.document.objectById(second.last)!.props['content'],
      contains('Input'),
    );
    expect(
      kitApi.store.document.objectById(second.last)!.props['content'],
      contains('Output'),
    );
    expect(
      kitApi.store.document.objectById(second.last)!.props['prompt'],
      isNot(kitApi.store.document.objectById(second.last)!.props['reply']),
    );
  });

  test('formatLlmKitContent stacks Input and Output regions', () {
    final content = formatLlmKitContent(
      prompt: 'hello',
      reply: 'Echo: hello',
      model: 'deepseek-v4-flash',
      surface: 'completions',
    );
    expect(content, contains('Input'));
    expect(content, contains('hello'));
    expect(content, contains('Output'));
    expect(content, contains('Echo: hello'));
    expect(content, contains('deepseek-v4-flash · completions'));
    expect(content.indexOf('Input'), lessThan(content.indexOf('Output')));
    expect(content, isNot(contains('You:')));
  });

  test('formatLlmKitContent keeps prompt and error in separate regions', () {
    final content = formatLlmKitContent(
      prompt: 'ask',
      error: 'HTTP 500',
      surface: 'responses',
    );
    expect(content, contains('Input\nask'));
    expect(content, contains('Output\nHTTP 500'));
    expect(content, contains('responses'));
  });

  test('empty prompt shows Needs input on the compound kit', () {
    final empty = formatLlmKitContent(prompt: '');
    expect(empty, contains('Needs input'));
    expect(empty, contains('Input'));
    expect(empty, contains('Output'));
    expect(llmKitEmptyContent, contains('Needs input'));

    final filled = formatLlmKitContent(prompt: 'hello', reply: 'Echo: hello');
    expect(filled, isNot(contains('Needs input')));
    expect(formatLlmKitContent(prompt: ''), contains('Tools: none'));
    expect(
      formatLlmKitContent(prompt: 'hi', attachedTools: const ['list_kits']),
      contains('Tools: list_kits'),
    );
  });
}
