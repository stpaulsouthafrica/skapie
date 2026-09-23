import 'dart:io';

import 'package:skapie/scene/scene_document.dart';
import 'package:skapie/scene/scene_persistence.dart';

class BoardInfo {
  const BoardInfo({required this.name, required this.file});

  final String name;
  final File file;
}

/// Each board is a complete scene document. The original scene.json remains
/// the first board; new worlds live beside it under boards/.
class BoardCatalog {
  const BoardCatalog(this.initialSceneFile);

  final File initialSceneFile;

  Directory get _boardsDirectory =>
      Directory('${initialSceneFile.parent.path}/boards');
  File get _activeFile => File('${initialSceneFile.parent.path}/active-board');

  Future<List<BoardInfo>> list() async {
    final boards = <BoardInfo>[
      BoardInfo(name: 'Main board', file: initialSceneFile),
    ];
    if (!await _boardsDirectory.exists()) {
      return boards;
    }
    final files = <File>[];
    await for (final entry in _boardsDirectory.list()) {
      if (entry is File &&
          RegExp(r'^board-[0-9]+\.json$')
              .hasMatch(entry.uri.pathSegments.last)) {
        files.add(entry);
      }
    }
    files.sort((a, b) => _number(a).compareTo(_number(b)));
    for (final file in files) {
      boards.add(BoardInfo(name: 'Board ${_number(file)}', file: file));
    }
    return boards;
  }

  Future<BoardInfo> create() async {
    final existing = await list();
    final taken = {for (final board in existing.skip(1)) _number(board.file)};
    var next = 2;
    while (taken.contains(next)) {
      next++;
    }
    final file = File('${_boardsDirectory.path}/board-$next.json');
    await SceneFilePersistence(file).write(SceneDocument.empty());
    return BoardInfo(name: 'Board $next', file: file);
  }

  Future<BoardInfo> active() async {
    final boards = await list();
    if (!await _activeFile.exists()) {
      return boards.first;
    }
    final name = (await _activeFile.readAsString()).trim();
    for (final board in boards) {
      if (board.file.uri.pathSegments.last == name) {
        return board;
      }
    }
    return boards.first;
  }

  Future<void> activate(BoardInfo board) async {
    final path = board.file.absolute.path;
    final boards = await list();
    if (!boards.any((item) => item.file.absolute.path == path)) {
      throw ArgumentError('Unknown board: $path');
    }
    await _activeFile.parent.create(recursive: true);
    await _activeFile.writeAsString(board.file.uri.pathSegments.last);
  }

  int _number(File file) {
    final match = RegExp(r'board-([0-9]+)\.json$').firstMatch(file.path);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }
}
