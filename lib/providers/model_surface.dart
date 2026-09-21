enum ModelSurface {
  completions,
  responses,
  messages;

  String get id => name;

  static ModelSurface? tryParse(String? raw) {
    final value = raw?.trim().toLowerCase() ?? '';
    return switch (value) {
      'completions' || 'openai-completions' => ModelSurface.completions,
      'responses' || 'openai-responses' => ModelSurface.responses,
      'messages' || 'anthropic-messages' => ModelSurface.messages,
      _ => null,
    };
  }
}
