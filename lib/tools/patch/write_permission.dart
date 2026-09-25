import 'dart:io';

import 'package:flutter/services.dart';

/// Separate from RepositoryPermission: a read bookmark cannot satisfy this.
abstract class PatchWritePermission {
  Future<String?> chooseDirectory();
  Future<bool> canWrite(String path);
  Future<String?> exportProposal({required String name, required String text});
}

class SystemPatchWritePermission implements PatchWritePermission {
  const SystemPatchWritePermission();

  static const _channel = MethodChannel('skapie/repository');

  @override
  Future<String?> chooseDirectory() async {
    if (!Platform.isMacOS) return null;
    return _channel.invokeMethod<String>('chooseWriteDirectory');
  }

  @override
  Future<bool> canWrite(String path) async {
    if (!Platform.isMacOS) return false;
    return await _channel.invokeMethod<bool>('restoreWriteDirectory', path) ??
        false;
  }

  @override
  Future<String?> exportProposal({
    required String name,
    required String text,
  }) async {
    if (!Platform.isMacOS) return null;
    return _channel.invokeMethod<String>('exportPatchProposal', {
      'name': name,
      'text': text,
    });
  }
}
