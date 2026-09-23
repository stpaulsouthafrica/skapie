import 'dart:ui';

import 'package:skapie/agent/openai_compatible.dart';
import 'package:skapie/canvas/kit_links.dart';
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
        llmBodyBelongsToFrame(object, selected)) {
      return object;
    }
  }
  return null;
}

/// Frame + body for a selected LLM object, or null if selection is not LLM.
List<SceneObject>? llmKitMembers({
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
  SceneObject? frame;
  SceneObject? body;
  final role = selected.props[skapieRoleProp];
  if (role == 'body') {
    body = selected;
    for (final object in document.objects) {
      if (isLlmKitObject(object) &&
          object.props[skapieRoleProp] == 'frame' &&
          llmBodyBelongsToFrame(body, object)) {
        frame = object;
        break;
      }
    }
  } else if (role == 'frame') {
    frame = selected;
    body = llmKitBodyForSelection(document: document, selectedId: selectedId);
  } else {
    return [selected];
  }
  if (frame == null) {
    return [selected];
  }
  if (body == null || body.id == frame.id) {
    return [frame];
  }
  return [frame, body];
}

SceneObject? llmKitFrameForSelection({
  required SceneDocument document,
  required String? selectedId,
}) {
  final members = llmKitMembers(document: document, selectedId: selectedId);
  if (members == null) {
    return null;
  }
  for (final object in members) {
    if (object.props[skapieRoleProp] == 'frame') {
      return object;
    }
  }
  return null;
}

bool llmBodyBelongsToFrame(SceneObject body, SceneObject frame) {
  return body.x >= frame.x - 0.5 &&
      body.y >= frame.y - 0.5 &&
      body.x + body.width <= frame.x + frame.width + 0.5 &&
      body.y + body.height <= frame.y + frame.height + 0.5;
}

const String llmKitEmptyContent = 'Input\n\nOutput\n\nTools: none';

const String llmRunStatusProp = 'runStatus';

enum LlmRunStatus {
  ready,
  running,
  waitingForReview,
  completed,
  failed,
  cancelled,
}

String llmRunStatusLabel(LlmRunStatus status) {
  return switch (status) {
    LlmRunStatus.ready => 'Ready',
    LlmRunStatus.running => 'Running',
    LlmRunStatus.waitingForReview => 'Waiting for review',
    LlmRunStatus.completed => 'Completed',
    LlmRunStatus.failed => 'Failed',
    LlmRunStatus.cancelled => 'Cancelled',
  };
}

LlmRunStatus llmRunStatusOf(SceneObject? body, {required bool running}) {
  if (running) {
    return LlmRunStatus.running;
  }
  final stored = switch (body?.props[llmRunStatusProp]?.toString()) {
    'waitingForReview' => LlmRunStatus.waitingForReview,
    'completed' => LlmRunStatus.completed,
    'failed' => LlmRunStatus.failed,
    'cancelled' => LlmRunStatus.cancelled,
    'ready' => LlmRunStatus.ready,
    _ => null,
  };
  if (stored != null) {
    return stored;
  }
  final error = body?.props['error']?.toString().trim() ?? '';
  if (error.isNotEmpty) {
    return LlmRunStatus.failed;
  }
  final reply = body?.props['reply']?.toString().trim() ?? '';
  if (reply.isNotEmpty) {
    return LlmRunStatus.completed;
  }
  return LlmRunStatus.ready;
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
      model: body.props['model']?.toString(),
      surface: body.props['surface']?.toString(),
      attachedTools: llmAttachedToolNames(kitApi.store.document, bodyId),
    ),
  });
}

String formatLlmKitContent({
  required String prompt,
  String? reply,
  String? error,
  String? model,
  String? surface,
  AgentHttpDiagnostic? diagnostic,
  List<String>? attachedTools,
}) {
  final buffer = StringBuffer();
  final input = _shorten(prompt.trim(), 120);
  buffer.write('Input');
  if (input.isNotEmpty) {
    buffer.write('\n$input');
  }
  buffer.write('\n\nOutput');
  final fail = error?.trim();
  final text = reply?.trim();
  if (fail != null && fail.isNotEmpty) {
    buffer.write('\n$fail');
    final summary = diagnostic?.summary.trim();
    if (summary != null && summary.isNotEmpty && summary != fail) {
      buffer.write('\n\n$summary');
    }
  } else if (text != null && text.isNotEmpty) {
    buffer.write('\n$text');
  }
  final chrome = _kitChrome(model, surface ?? diagnostic?.surface);
  if (chrome.isNotEmpty) {
    buffer.write('\n\n$chrome');
  }
  final names = attachedTools ?? const <String>[];
  buffer.write('\n\nTools: ${names.isEmpty ? 'none' : names.join(', ')}');
  return buffer.toString();
}

List<String> llmAttachedToolNames(SceneDocument document, String llmBodyId) {
  final names = <String>[];
  for (final object in document.objects) {
    if (!kitLinksOf(object)
        .any((link) => link.to == llmBodyId && link.port == llmToolsPort)) {
      continue;
    }
    final name = object.props['toolName']?.toString().trim() ?? '';
    if (name.isNotEmpty && !names.contains(name)) {
      names.add(name);
    }
  }
  return names;
}

String _kitChrome(String? model, String? surface) {
  final id = model?.trim() ?? '';
  final seat = surface?.trim() ?? '';
  if (id.isEmpty && seat.isEmpty) {
    return '';
  }
  if (id.isEmpty) {
    return seat;
  }
  if (seat.isEmpty) {
    return id;
  }
  return '$id · $seat';
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
  String? surface,
  AgentHttpDiagnostic? diagnostic,
}) {
  final body = kitApi.store.document.objectById(bodyId);
  if (body == null ||
      !isLlmKitObject(body) ||
      body.props[skapieRoleProp] != 'body') {
    throw StateError('harness.llm body is missing');
  }
  final seat = surface ?? diagnostic?.surface;
  kitApi.updateProps(body.id, {
    'prompt': prompt,
    'reply': reply ?? '',
    'error': error ?? '',
    'model': model ?? '',
    'provider': provider ?? '',
    'surface': seat ?? '',
    llmRunStatusProp: (error?.trim().isNotEmpty ?? false)
        ? 'failed'
        : 'completed',
    'content': formatLlmKitContent(
      prompt: prompt,
      reply: reply,
      error: error,
      model: model,
      surface: seat,
      diagnostic: diagnostic,
      attachedTools: llmAttachedToolNames(kitApi.store.document, body.id),
    ),
  });
}

String _shorten(String text, int max) {
  if (text.length <= max) {
    return text;
  }
  return '${text.substring(0, max)}...';
}
