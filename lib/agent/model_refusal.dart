/// A provider explicitly declined a request in an otherwise successful reply.
class ModelRefusalException implements Exception {
  const ModelRefusalException();

  @override
  String toString() => 'Model declined this request';
}

void rejectChatRefusal(Map<dynamic, dynamic> choice) {
  if (choice['finish_reason'] == 'content_filter') {
    throw const ModelRefusalException();
  }
  final message = choice['message'];
  if (message is Map && _hasRefusal(message['refusal'])) {
    throw const ModelRefusalException();
  }
}

void rejectMessageRefusal(Map<dynamic, dynamic> message) {
  if (_hasRefusal(message['refusal'])) {
    throw const ModelRefusalException();
  }
}

void rejectResponsesRefusal(Map<dynamic, dynamic> body) {
  if (_hasRefusal(body['refusal'])) {
    throw const ModelRefusalException();
  }
  final output = body['output'];
  if (output is! List) return;
  for (final item in output) {
    if (item is! Map) continue;
    if (item['type'] == 'refusal' || _hasRefusal(item['refusal'])) {
      throw const ModelRefusalException();
    }
    final content = item['content'];
    if (content is! List) continue;
    for (final block in content) {
      if (block is Map &&
          (block['type'] == 'refusal' || _hasRefusal(block['refusal']))) {
        throw const ModelRefusalException();
      }
    }
  }
}

void rejectAnthropicRefusal(Map<dynamic, dynamic> body) {
  if (body['stop_reason'] == 'refusal' || _hasRefusal(body['refusal'])) {
    throw const ModelRefusalException();
  }
  final content = body['content'];
  if (content is! List) return;
  for (final block in content) {
    if (block is Map &&
        (block['type'] == 'refusal' || _hasRefusal(block['refusal']))) {
      throw const ModelRefusalException();
    }
  }
}

bool _hasRefusal(Object? value) =>
    value != null && value != false && '$value'.trim().isNotEmpty;
