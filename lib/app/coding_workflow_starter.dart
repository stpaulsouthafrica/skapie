import 'dart:ui';

import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/tools/world/kits.dart';

/// The lean default board: a task, a model, a thread, an output, a repository
/// grant, the four coding tools, and the offline Skapie Extensions docs.
/// Nothing here runs a model or touches disk.
Rect addCodingWorkflowStarter(KitApi kitApi, {required Offset origin}) {
  if (kitApi.store.document.objects.isNotEmpty) {
    throw StateError('Start on an empty board.');
  }

  final placements = <({String key, String kitId, Offset at})>[
    (key: 'task', kitId: boardTextKitId, at: const Offset(0, 0)),
    (key: 'llm', kitId: harnessLlmKitId, at: const Offset(700, 0)),
    (
      key: 'conversation',
      kitId: harnessConversationKitId,
      at: const Offset(1120, 0),
    ),
    (key: 'output', kitId: boardTextKitId, at: const Offset(700, 420)),
    (
      key: 'repository',
      kitId: codingRepositoryKitId,
      at: const Offset(0, 390),
    ),
    (key: 'read', kitId: worldToolKitId('read'), at: const Offset(350, 350)),
    (key: 'write', kitId: worldToolKitId('write'), at: const Offset(350, 470)),
    (key: 'edit', kitId: worldToolKitId('edit'), at: const Offset(350, 590)),
    (key: 'shell', kitId: worldToolKitId('shell'), at: const Offset(350, 710)),
    (
      key: 'extensions',
      kitId: skapieExtensionsKitId,
      at: const Offset(1120, 420),
    ),
  ];

  // Check the shelf before mutating the scene. Packages can be reloaded.
  for (final entry in placements) {
    if (kitApi.getKit(entry.kitId) == null) {
      throw StateError('Missing public kit: ${entry.kitId}');
    }
  }

  final frames = <String, String>{};
  for (final entry in placements) {
    final ids = kitApi.instantiate(entry.kitId, origin: origin + entry.at);
    frames[entry.key] = ids.first;
  }
  kitApi.updateProps(frames['task']!, {
    'content': '',
    kitNameProp: 'Task',
  });
  kitApi.updateProps(frames['output']!, {kitNameProp: 'Output'});

  void wire(String sourceKey, KitPortKind sourceKind, String targetKey, KitPortKind targetKind) {
    final ports = kitPorts(kitApi.store.document);
    final from = ports.singleWhere(
      (port) => port.frameId == frames[sourceKey] && port.kind == sourceKind,
    );
    final to = ports.singleWhere(
      (port) => port.frameId == frames[targetKey] && port.kind == targetKind,
    );
    if (!kitPortsConnect(from.kind, to.kind)) {
      throw StateError('Incompatible public ports: $sourceKey → $targetKey');
    }
    connectKitPorts(kitApi: kitApi, from: from, to: to);
  }

  wire('task', KitPortKind.textOut, 'llm', KitPortKind.llmInput);
  wire(
    'llm',
    KitPortKind.llmConversation,
    'conversation',
    KitPortKind.conversationIn,
  );
  wire('llm', KitPortKind.llmOutput, 'output', KitPortKind.textIn);
  wire('extensions', KitPortKind.extensionsOut, 'llm', KitPortKind.llmContext);

  wire('repository', KitPortKind.repositoryOut, 'read', KitPortKind.toolRepository);
  for (final key in ['write', 'edit', 'shell']) {
    wire(
      'repository',
      KitPortKind.repositoryWriteOut,
      key,
      KitPortKind.toolWriteScope,
    );
  }
  for (final key in ['read', 'write', 'edit', 'shell']) {
    wire(key, KitPortKind.toolOut, 'llm', KitPortKind.llmTools);
  }

  return Rect.fromLTWH(origin.dx, origin.dy, 1500, 850);
}
