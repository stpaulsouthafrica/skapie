import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';
import 'package:skapie/tools/coding/coding_tools.dart';
import 'package:skapie/tools/coding/edit_tool.dart';
import 'package:skapie/tools/coding/read_tool.dart';
import 'package:skapie/tools/coding/shell_tool.dart';
import 'package:skapie/tools/coding/write_tool.dart';
import 'package:skapie/tools/patch/write_permission.dart';
import 'package:skapie/tools/repository/repository_permission.dart';

class _ReadGrant implements RepositoryPermission {
  const _ReadGrant(this.allowed);
  final bool allowed;
  @override
  Future<String?> chooseDirectory() async => null;
  @override
  Future<bool> canRead(String path) async => allowed;
}

class _WriteGrant implements PatchWritePermission {
  const _WriteGrant(this.allowed);
  final bool allowed;
  @override
  Future<String?> chooseDirectory() async => null;
  @override
  Future<bool> canWrite(String path) async => allowed;
  @override
  Future<String?> exportProposal({
    required String name,
    required String text,
  }) async => null;
}

void main() {
  late Directory repo;

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('skapie-coding-');
  });
  tearDown(() async => repo.delete(recursive: true));

  test('total: the shelf is exactly the four coding tools', () {
    expect(codingToolNames, {'read', 'write', 'edit', 'shell'});
  });

  test('read lists and reads inside the grant, and refuses without it', () async {
    await File('${repo.path}/hello.txt').writeAsString('one\ntwo\n');
    final tool = readTool(path: repo.path, permission: const _ReadGrant(true));
    final list = await tool.run({'action': 'list'});
    expect(list['ok'], isTrue);
    expect(list['files'], contains('hello.txt'));
    final read = await tool.run({'action': 'read', 'path': 'hello.txt'});
    expect(read['ok'], isTrue);
    expect(read['content'], contains('one'));

    final denied = readTool(
      path: repo.path,
      permission: const _ReadGrant(false),
    );
    expect((await denied.run({'action': 'list'}))['ok'], isFalse);
  });

  test('write creates and replaces, and refuses without the write grant', () async {
    final tool = writeTool(
      path: repo.path,
      permission: const _WriteGrant(true),
    );
    final first = await tool.run({'path': 'new.txt', 'content': 'hi'});
    expect(first['ok'], isTrue);
    expect(first['created'], isTrue);
    expect(await File('${repo.path}/new.txt').readAsString(), 'hi');

    final replace = await tool.run({'path': 'new.txt', 'content': 'bye'});
    expect(replace['ok'], isTrue);
    expect(replace['created'], isFalse);
    expect(await File('${repo.path}/new.txt').readAsString(), 'bye');

    final outside = await tool.run({
      'path': '../escape.txt',
      'content': 'x',
    });
    expect(outside['ok'], isFalse);

    final denied = writeTool(
      path: repo.path,
      permission: const _WriteGrant(false),
    );
    expect((await denied.run({'path': 'x.txt', 'content': 'x'}))['ok'], isFalse);
  });

  test('edit replaces one exact match on disk', () async {
    final file = File('${repo.path}/code.txt');
    await file.writeAsString('a = 1;\n');
    final tool = editTool(
      path: repo.path,
      permission: const _WriteGrant(true),
    );
    final result = await tool.run({
      'path': 'code.txt',
      'oldText': 'a = 1;',
      'newText': 'a = 2;',
    });
    expect(result['ok'], isTrue);
    expect(await file.readAsString(), 'a = 2;\n');

    final stale = await tool.run({
      'path': 'code.txt',
      'oldText': 'not there',
      'newText': 'x',
    });
    expect(stale['ok'], isFalse);
  });

  test('shell runs in the grant and refuses paths outside it', () async {
    final tool = shellTool(
      path: repo.path,
      permission: const _WriteGrant(true),
    );
    final ok = await tool.run({'command': 'pwd'});
    expect(ok['exitCode'], 0);
    expect((ok['stdout'] as String).trim(), isNotEmpty);

    final escape = await tool.run({'command': 'cat /etc/hosts'});
    expect(escape['ok'], isFalse);
    expect(escape['error'], contains('outside the repository'));

    final denied = shellTool(
      path: repo.path,
      permission: const _WriteGrant(false),
    );
    expect((await denied.run({'command': 'pwd'}))['ok'], isFalse);
  });

  test('llmToolOffer needs a live read or write cable for each tool', () {
    final api = createAppKitApi(store: SceneStore());
    final llm = api.instantiate(harnessLlmKitId, origin: Offset.zero);
    final repository = api.instantiate(
      codingRepositoryKitId,
      origin: const Offset(0, 300),
    );
    final read = api.instantiate('tools.read', origin: const Offset(400, 0));
    final write = api.instantiate('tools.write', origin: const Offset(400, 200));
    attachToolKit(kitApi: api, toolObjectId: read.first, llmBodyId: llm.last);
    attachToolKit(kitApi: api, toolObjectId: write.first, llmBodyId: llm.last);

    var offer = llmToolOffer(kitApi: api, llmBodyId: llm.last);
    expect(offer.tools, isEmpty);
    expect(
      offer.filtered.map((item) => item.reason),
      containsAll([
        'Repository read grant missing',
        'Repository write grant missing',
      ]),
    );

    api.updateProps(repository.first, {
      repositoryPathProp: '/tmp/repository',
      repositoryWritePathProp: '/tmp/repository',
    });
    connectRepositoryToTool(
      kitApi: api,
      repositoryFrameId: repository.first,
      toolFrameId: read.first,
    );
    connectRepositoryToTool(
      kitApi: api,
      repositoryFrameId: repository.first,
      toolFrameId: write.first,
      port: toolWritePort,
    );
    offer = llmToolOffer(kitApi: api, llmBodyId: llm.last);
    expect(offer.names.toSet(), {'read', 'write'});
  });
}
