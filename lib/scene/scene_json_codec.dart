double readDouble(Map<String, Object?> json, String key, [double? fallback]) {
  final value = json[key];
  if (value == null) {
    if (fallback != null) {
      return fallback;
    }
    throw FormatException('Missing number "$key"');
  }
  if (value is! num) {
    throw FormatException('Expected number "$key"');
  }
  return value.toDouble();
}

int readInt(Map<String, Object?> json, String key, [int fallback = 0]) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  if (value is! num) {
    throw FormatException('Expected number "$key"');
  }
  return value.toInt();
}

bool readBool(Map<String, Object?> json, String key, bool fallback) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  if (value is! bool) {
    throw FormatException('Expected bool "$key"');
  }
  return value;
}

Map<String, Object?> asJsonMap(Object? value, String context) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, v) => MapEntry(key.toString(), v));
  }
  throw FormatException('Expected object for $context');
}

Map<String, Object?> readProps(Object? value) {
  if (value == null) {
    return const {};
  }
  return Map<String, Object?>.from(asJsonMap(value, 'props'));
}
