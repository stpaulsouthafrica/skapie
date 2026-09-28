import 'package:flutter/foundation.dart';

enum HostStatusSeverity { error, warning }

class HostStatusItem {
  const HostStatusItem({
    required this.key,
    required this.message,
    required this.severity,
  });

  /// Stable id so a later success can clear the matching error.
  final String key;
  final String message;
  final HostStatusSeverity severity;

  bool get isError => severity == HostStatusSeverity.error;
}

/// Host-owned list of things the user should know about: package faults and
/// grant/tool denials. Only shown while there is something to say.
class HostStatusLog extends ChangeNotifier {
  final Map<String, HostStatusItem> _items = {};

  List<HostStatusItem> get items => List.unmodifiable(_items.values);

  bool get hasErrors => _items.values.any((item) => item.isError);

  void report({
    required String key,
    required String message,
    HostStatusSeverity severity = HostStatusSeverity.error,
  }) {
    final existing = _items[key];
    if (existing != null &&
        existing.message == message &&
        existing.severity == severity) {
      return;
    }
    _items[key] = HostStatusItem(
      key: key,
      message: message,
      severity: severity,
    );
    notifyListeners();
  }

  void clear(String key) {
    if (_items.remove(key) != null) {
      notifyListeners();
    }
  }

  void clearWhere(bool Function(String key) test) {
    final before = _items.length;
    _items.removeWhere((key, _) => test(key));
    if (_items.length != before) {
      notifyListeners();
    }
  }
}
