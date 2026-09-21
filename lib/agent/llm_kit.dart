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

SceneObject? findLlmKitBody(KitApi kitApi) {
  for (final object in kitApi.store.document.objects) {
    if (object.props[skapieKitProp] == harnessLlmKitId &&
        object.props[skapieRoleProp] == 'body') {
      return object;
    }
  }
  return null;
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

/// Spawn or update the single `harness.llm` kit via [KitApi] only.
void publishLlmKit({
  required KitApi kitApi,
  required String prompt,
  String? reply,
  String? error,
  String? model,
  String? provider,
  AgentHttpDiagnostic? diagnostic,
}) {
  ensureHarnessLlmKit(kitApi);
  var body = findLlmKitBody(kitApi);
  if (body == null) {
    kitApi.instantiate(harnessLlmKitId, origin: llmKitOrigin);
    body = findLlmKitBody(kitApi);
  }
  if (body == null) {
    throw StateError('harness.llm body text is missing');
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
