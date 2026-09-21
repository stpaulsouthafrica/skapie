import 'package:skapie/agent/openai_compatible.dart';

String openaiResponsesUrl(String baseUrl) {
  return '${openaiNormalizedBaseUrl(baseUrl)}/responses';
}

String anthropicMessagesUrl(String baseUrl) {
  return '${openaiNormalizedBaseUrl(baseUrl)}/messages';
}

String extractResponsesOutputText(Map<dynamic, dynamic> body) {
  final shortcut = body['output_text'];
  if (shortcut is String && shortcut.trim().isNotEmpty) {
    return shortcut;
  }
  final output = body['output'];
  if (output is! List) {
    return '';
  }
  final buffer = StringBuffer();
  for (final item in output) {
    if (item is! Map) {
      continue;
    }
    final type = item['type']?.toString();
    if (type == 'output_text') {
      final text = item['text'];
      if (text is String) {
        buffer.write(text);
      }
      continue;
    }
    if (type != null && type != 'message') {
      continue;
    }
    final content = item['content'];
    if (content is String) {
      buffer.write(content);
      continue;
    }
    if (content is! List) {
      continue;
    }
    for (final block in content) {
      if (block is! Map) {
        continue;
      }
      final blockType = block['type']?.toString();
      if (blockType == 'output_text' || blockType == 'text') {
        final text = block['text'];
        if (text is String) {
          buffer.write(text);
        }
      }
    }
  }
  return buffer.toString();
}

String extractAnthropicMessageText(Map<dynamic, dynamic> body) {
  final content = body['content'];
  if (content is String) {
    return content;
  }
  if (content is! List) {
    return '';
  }
  final buffer = StringBuffer();
  for (final block in content) {
    if (block is! Map) {
      continue;
    }
    final type = block['type']?.toString();
    if (type == 'text' || type == null) {
      final text = block['text'];
      if (text is String) {
        buffer.write(text);
      }
    }
  }
  return buffer.toString();
}
