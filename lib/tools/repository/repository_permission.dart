import 'dart:io';

import 'package:flutter/services.dart';

/// The board stores the repository path. macOS stores the folder grant in an
/// app-scoped bookmark so opening the board again can restore read access.
abstract class RepositoryPermission {
  Future<String?> chooseDirectory();

  Future<bool> canRead(String path);
}

class SystemRepositoryPermission implements RepositoryPermission {
  const SystemRepositoryPermission();

  static const _channel = MethodChannel('skapie/repository');

  @override
  Future<String?> chooseDirectory() async {
    if (!Platform.isMacOS) {
      return null;
    }
    return _channel.invokeMethod<String>('chooseDirectory');
  }

  @override
  Future<bool> canRead(String path) async {
    if (!Platform.isMacOS) {
      return false;
    }
    return await _channel.invokeMethod<bool>('restoreDirectory', path) ?? false;
  }
}
