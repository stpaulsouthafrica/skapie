import 'dart:ui';

import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';

const Offset llmKitOrigin = Offset(24, 24);

void ensureHarnessLlmKit(KitApi kitApi) {
  if (kitApi.getKit(harnessLlmKitId) == null) {
    kitApi.registerKit(harnessLlmRecipe);
  }
}

bool isLlmKitObject(SceneObject object) {
  return object.props[skapieKitProp] == harnessLlmKitId;
}

SceneObject? findLlmKitBody(KitApi kitApi) {
  return llmKitBodyForSelection(
    document: kitApi.store.document,
    selectedId: kitApi.store.document.objects
        .where(
          (object) =>
              isLlmKitObject(object) && object.props[skapieRoleProp] == 'body',
        )
        .map((object) => object.id)
        .firstOrNull,
  );
}

SceneObject? llmKitBodyForSelection({
  required SceneDocument document,
  required String? selectedId,
}) {
  if (selectedId == null) {
    return null;
  }
  final selected = document.objectById(selectedId);
  if (selected == null || !isLlmKitObject(selected)) {
    return null;
  }
  if (selected.props[skapieRoleProp] == 'body') {
    return selected;
  }
  for (final object in document.objects) {
    if (isLlmKitObject(object) &&
        object.props[skapieRoleProp] == 'body' &&
        _bodyBelongsToFrame(object, selected)) {
      return object;
    }
  }
  return null;
}

bool _bodyBelongsToFrame(SceneObject body, SceneObject frame) {
  return body.x >= frame.x - 0.5 &&
      body.y >= frame.y - 0.5 &&
      body.x + body.width <= frame.x + frame.width + 0.5 &&
      body.y + body.height <= frame.y + frame.height + 0.5;
}

void setLlmKitPrompt({
  required KitApi kitApi,
  required String bodyId,
  required String prompt,
}) {
  final body = kitApi.store.document.objectById(bodyId);
  if (body == null || !isLlmKitObject(body)) {
    return;
  }
  kitApi.updateProps(bodyId, {
    'prompt': prompt,
    'content': formatLlmKitContent(
      prompt: prompt,
      reply: body.props['reply']?.toString(),
      error: body.props['error']?.toString(),
    ),
  });
}

String formatLlmKitContent({
  required String prompt,
  String? reply,
  String? error,
  AgentHttpDiagnostic? diagnostic,
}) {
  final buffer = StringBuffer('You: ${_shorten(prompt.trim(), 120)}');
  final text = reply?.trim();
  if (text != null && text.isNotEmpty) {
    buffer.write('\n\n$text');
  }
  final fail = error?.trim();
  if (fail != null && fail.isNotEmpty) {
    buffer.write('\n\n$fail');
  }
  final summary = diagnostic?.summary.trim();
  if (fail != null &&
      summary != null &&
      summary.isNotEmpty &&
      summary != fail) {
    buffer.write('\n\n$summary');
  }
  return buffer.toString();
}

/// Update a compound LLM kit body via [KitApi] only. Does not instantiate.
void publishLlmKit({
  required KitApi kitApi,
  required String bodyId,
  required String prompt,
  String? reply,
  String? error,
  String? model,
  String? provider,
  AgentHttpDiagnostic? diagnostic,
}) {
  final body = kitApi.store.document.objectById(bodyId);
  if (body == null ||
      !isLlmKitObject(body) ||
      body.props[skapieRoleProp] != 'body') {
    throw StateError('harness.llm body is missing');
  }
  kitApi.updateProps(body.id, {
    'prompt': prompt,
    'reply': reply ?? '',
    'error': error ?? '',
    'model': model ?? '',
    'provider': provider ?? '',
    'content': formatLlmKitContent(
      prompt: prompt,
      reply: reply,
      error: error,
      diagnostic: diagnostic,
    ),
  });
}

String _shorten(String text, int max) {
  if (text.length <= max) {
    return text;
  }
  return '${text.substring(0, max)}...';
}
