import 'dart:ui';

import 'package:skapie/agent/llm_kit.dart';
import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';

enum BoardIssueKind {
  incompatible,
  tooMany,
  missingInput,
  staleEndpoint,
  missingGrant,
  cycle,
}

/// Errors block the LLM runs they feed. Warnings sit on kits no run reads.
enum BoardIssueSeverity { error, warning }

/// Which end of a marked cable has nothing to plug into.
enum CableDangling { none, start, end }

class BoardIssue {
  const BoardIssue({
    required this.kind,
    required this.severity,
    required this.message,
    required this.frameId,
    this.port,
    this.cableId,
    this.blocks = const {},
  });

  final BoardIssueKind kind;
  final BoardIssueSeverity severity;
  final String message;

  /// Kit to select when the issue is opened.
  final String frameId;
  final KitPortKind? port;
  final String? cableId;

  /// LLM bodies whose Run this issue stops.
  final Set<String> blocks;
}

/// A cable drawn in the invalid style. [extra] cables are not in
/// [sceneCables]; nothing flows along them.
class MarkedCable {
  const MarkedCable({
    required this.cable,
    required this.kind,
    required this.message,
    this.dangling = CableDangling.none,
    this.extra = false,
  });

  final SceneCable cable;
  final BoardIssueKind kind;
  final String message;
  final CableDangling dangling;
  final bool extra;
}

class BoardValidation {
  const BoardValidation({required this.issues, required this.markedCables});

  static const empty = BoardValidation(issues: [], markedCables: []);

  final List<BoardIssue> issues;
  final List<MarkedCable> markedCables;

  Set<String> get markedIds => {
    for (final marked in markedCables) marked.cable.id,
  };

  List<SceneCable> get extraCables => [
    for (final marked in markedCables)
      if (marked.extra) marked.cable,
  ];

  MarkedCable? markOf(String cableId) {
    for (final marked in markedCables) {
      if (marked.cable.id == cableId) {
        return marked;
      }
    }
    return null;
  }

  /// Errors that stop [llmBodyId] from running. [inputSupplied] skips the
  /// Input requirement when the caller already holds the prompt.
  List<BoardIssue> runBlockers(String llmBodyId, {bool inputSupplied = false}) {
    return [
      for (final issue in issues)
        if (issue.severity == BoardIssueSeverity.error &&
            issue.blocks.contains(llmBodyId) &&
            !(inputSupplied && issue.port == KitPortKind.llmInput))
          issue,
    ];
  }
}

class CableRefusal {
  const CableRefusal(this.port, this.reason);

  /// The port under the cursor that the drag may not land on.
  final KitPort port;
  final String reason;
}

/// Why a cable dragged from [kind] on [frameId] may not land at [world].
/// Null when nothing is there or the landing is valid.
CableRefusal? cableDragRefusal(
  SceneDocument document,
  String frameId,
  KitPortKind kind,
  Offset world,
) {
  final ports = kitPorts(document);
  final hit = hitKitPort(ports, world);
  if (hit == null || (hit.frameId == frameId && hit.kind == kind)) {
    return null;
  }
  final reason = kitPortRefusal(kind, hit.kind);
  if (reason != null) {
    return CableRefusal(hit, reason);
  }
  final source = ports
      .where((port) => port.frameId == frameId && port.kind == kind)
      .firstOrNull;
  if (source != null && source.peerId == hit.peerId) {
    return CableRefusal(hit, 'A kit cannot cable into itself');
  }
  return null;
}

/// Stable enough to remember which issue the user is inspecting.
String boardIssueKey(BoardIssue issue) {
  return [
    issue.kind.name,
    issue.frameId,
    issue.port?.name ?? '',
    issue.message,
  ].join('|');
}

/// Ports an issue is about. A missing requirement points at every port in
/// its group; a cable issue without a port points at both cable ends.
List<KitPort> boardIssuePorts(SceneDocument document, BoardIssue issue) {
  final ports = kitPorts(document);
  final kind = issue.port;
  if (kind != null) {
    final group = kitPortSpecOf(kind).requiredGroup;
    final grouped =
        group != null &&
        (issue.kind == BoardIssueKind.missingInput ||
            issue.kind == BoardIssueKind.missingGrant);
    return [
      for (final port in ports)
        if (port.frameId == issue.frameId &&
            (grouped ? port.spec.requiredGroup == group : port.kind == kind))
          port,
    ];
  }
  final cableId = issue.cableId;
  if (cableId == null) {
    return const [];
  }
  final cable = [
    ...sceneCables(document),
    ...validateBoard(document).extraCables,
  ].where((item) => item.id == cableId).firstOrNull;
  if (cable == null) {
    return const [];
  }
  return [
    for (final port in ports)
      if ((port.frameId == cable.sourceId && port.kind == cable.fromKind) ||
          (port.frameId == cable.targetFrameId && port.kind == cable.toKind))
        port,
  ];
}

/// LLM bodies whose Run is blocked right now.
Set<String> blockedLlmBodies(BoardValidation validation) {
  return {
    for (final issue in validation.issues)
      if (issue.severity == BoardIssueSeverity.error) ...issue.blocks,
  };
}

/// Stub length for a cable whose far end was deleted.
const double staleCableReach = 56;

BoardValidation validateBoard(
  SceneDocument document, {
  String? resizeFrameId,
  double? resizeHeight,
}) {
  final ports = kitPorts(
    document,
    resizeFrameId: resizeFrameId,
    resizeHeight: resizeHeight,
  );
  final cables = sceneCables(
    document,
    resizeFrameId: resizeFrameId,
    resizeHeight: resizeHeight,
  );
  return _Validator(document, ports, cables).run();
}

class _Draft {
  _Draft(this.kind, this.message, this.frameId, {this.port, this.cableId});

  final BoardIssueKind kind;
  final String message;
  final String frameId;
  final KitPortKind? port;
  final String? cableId;
}

class _Validator {
  _Validator(this.document, this.ports, this.cables) {
    for (final port in ports) {
      byFrame.putIfAbsent(port.frameId, () => []).add(port);
    }
  }

  final SceneDocument document;
  final List<KitPort> ports;
  final List<SceneCable> cables;
  final byFrame = <String, List<KitPort>>{};
  final drafts = <_Draft>[];
  final marked = <MarkedCable>[];

  BoardValidation run() {
    _links();
    _multiplicity();
    _required();
    _liveGrants();
    _replyLoops();
    final issues = <BoardIssue>[];
    for (final draft in drafts) {
      final blocks = draft.kind == BoardIssueKind.cycle
          ? _cycleBodies[draft]!
          : _affectedLlms(draft);
      issues.add(
        BoardIssue(
          kind: draft.kind,
          severity: blocks.isEmpty
              ? BoardIssueSeverity.warning
              : BoardIssueSeverity.error,
          message: draft.message,
          frameId: draft.frameId,
          port: draft.port,
          cableId: draft.cableId,
          blocks: blocks,
        ),
      );
    }
    return BoardValidation(
      issues: List.unmodifiable(issues),
      markedCables: List.unmodifiable(marked),
    );
  }

  String _name(String frameId) {
    final frame = document.objectById(frameId);
    return frame == null ? 'a deleted kit' : kitDisplayName(document, frame);
  }

  /// Saved links that no descriptor pair explains: stale or wrong type.
  void _links() {
    final drawn = {for (final cable in cables) cable.id};
    for (final entry in byFrame.entries) {
      final peers = {for (final port in entry.value) port.peerId};
      for (final peerId in peers) {
        final owner = document.objectById(peerId);
        if (owner == null) {
          continue;
        }
        final ownerPorts = [
          for (final port in entry.value)
            if (port.peerId == peerId) port,
        ];
        for (final link in kitLinksOf(owner)) {
          final id = '$peerId|${link.id}';
          if (drawn.contains(id)) {
            continue;
          }
          final mine = _ownerPortFor(ownerPorts, link) ?? ownerPorts.first;
          final target = document.objectById(link.to) == null
              ? null
              : kitFrameForSelection(document: document, selectedId: link.to);
          if (target == null) {
            _stale(id, mine, link);
          } else {
            _incompatible(id, mine, target, link);
          }
        }
      }
    }
  }

  KitPort? _ownerPortFor(List<KitPort> ownerPorts, KitLink link) {
    for (final port in ownerPorts) {
      final spec = port.spec;
      if (spec.isOutput) {
        final reaches = allKitPortSpecs.any(
          (input) =>
              !input.isOutput &&
              input.linkOwner == PortLinkOwner.source &&
              input.storedPort == link.port &&
              input.takes(spec.value),
        );
        if (reaches) {
          return port;
        }
      } else if (spec.linkOwner == PortLinkOwner.target &&
          spec.storedPort == link.port) {
        return port;
      }
    }
    return null;
  }

  void _stale(String id, KitPort mine, KitLink link) {
    final output = mine.spec.isOutput;
    final message = '${mine.spec.label} points at a kit that was deleted';
    final cable = SceneCable(
      id: 'stale:$id',
      ownerId: mine.peerId,
      port: link.port,
      sourceId: output ? mine.frameId : '',
      targetFrameId: output ? '' : mine.frameId,
      from: output
          ? mine.center
          : mine.center - const Offset(staleCableReach, 0),
      to: output ? mine.center + const Offset(staleCableReach, 0) : mine.center,
      color: kitSwatches.first,
      targetBodyId: link.to,
      affectsRun: false,
      fromKind: output ? mine.kind : null,
      toKind: output ? null : mine.kind,
      fromPeerId: output ? mine.peerId : null,
      toPeerId: output ? null : mine.peerId,
    );
    marked.add(
      MarkedCable(
        cable: cable,
        kind: BoardIssueKind.staleEndpoint,
        message: message,
        dangling: output ? CableDangling.end : CableDangling.start,
        extra: true,
      ),
    );
    drafts.add(
      _Draft(
        BoardIssueKind.staleEndpoint,
        message,
        mine.frameId,
        port: mine.kind,
        cableId: cable.id,
      ),
    );
  }

  void _incompatible(
    String id,
    KitPort mine,
    SceneObject target,
    KitLink link,
  ) {
    final targetPorts = byFrame[target.id] ?? const <KitPort>[];
    final named = targetPorts
        .where(
          (port) => !port.spec.isOutput && port.spec.storedPort == link.port,
        )
        .firstOrNull;
    final theirs =
        named ??
        targetPorts
            .where((port) => port.spec.isOutput != mine.spec.isOutput)
            .firstOrNull;
    final message = named == null
        ? '${_name(target.id)} has no ${link.port} port'
        : kitPortRefusal(mine.kind, named.kind) ??
              '${mine.spec.label} → ${named.spec.label} is not allowed';
    final far =
        theirs?.center ?? Offset(target.x, target.y + target.height / 2);
    final output = mine.spec.isOutput;
    final cable = SceneCable(
      id: 'invalid:$id',
      ownerId: mine.peerId,
      port: link.port,
      sourceId: output ? mine.frameId : target.id,
      targetFrameId: output ? target.id : mine.frameId,
      from: output ? mine.center : far,
      to: output ? far : mine.center,
      color: kitSwatches.first,
      targetBodyId: link.to,
      affectsRun: false,
      fromKind: output ? mine.kind : theirs?.kind,
      toKind: output ? theirs?.kind : mine.kind,
      fromPeerId: output ? mine.peerId : theirs?.peerId,
      toPeerId: output ? theirs?.peerId : mine.peerId,
    );
    marked.add(
      MarkedCable(
        cable: cable,
        kind: BoardIssueKind.incompatible,
        message: message,
        extra: true,
      ),
    );
    drafts.add(
      _Draft(
        BoardIssueKind.incompatible,
        message,
        mine.frameId,
        port: mine.kind,
        cableId: cable.id,
      ),
    );
    if (target.id != mine.frameId) {
      _alsoBlocks[drafts.last] = target.id;
    }
  }

  final _alsoBlocks = <_Draft, String>{};

  void _multiplicity() {
    for (final port in ports) {
      if (port.spec.isOutput ||
          port.spec.multiplicity != PortMultiplicity.one) {
        continue;
      }
      final into = [
        for (final cable in cables)
          if (cable.toKind == port.kind && cable.toPeerId == port.peerId) cable,
      ];
      if (into.length < 2) {
        continue;
      }
      final message = '${port.spec.label} takes one cable, not ${into.length}';
      for (final extra in into.skip(1)) {
        marked.add(
          MarkedCable(
            cable: extra,
            kind: BoardIssueKind.tooMany,
            message: message,
          ),
        );
      }
      drafts.add(
        _Draft(
          BoardIssueKind.tooMany,
          message,
          port.frameId,
          port: port.kind,
          cableId: into.last.id,
        ),
      );
    }
  }

  bool _connected(KitPort port) {
    return cables.any(
      (cable) =>
          (cable.fromKind == port.kind && cable.fromPeerId == port.peerId) ||
          (cable.toKind == port.kind && cable.toPeerId == port.peerId),
    );
  }

  void _required() {
    for (final entry in byFrame.entries) {
      final groups = <String, List<KitPort>>{};
      for (final port in entry.value) {
        final group = port.spec.requiredGroup;
        if (group != null) {
          groups.putIfAbsent(group, () => []).add(port);
        }
      }
      for (final group in groups.values) {
        final first = group.first;
        final grant = group.any(
          (port) => port.spec.value == PortValue.repository,
        );
        final kind = grant
            ? BoardIssueKind.missingGrant
            : BoardIssueKind.missingInput;
        if (!group.any(_connected)) {
          drafts.add(
            _Draft(
              kind,
              first.spec.requiredMessage ?? 'Needs ${first.spec.label}',
              entry.key,
              port: first.kind,
            ),
          );
          continue;
        }
        for (final port in group) {
          if (port.kind == KitPortKind.llmInput &&
              llmCableInput(document, port.peerId).trim().isEmpty) {
            drafts.add(
              _Draft(
                BoardIssueKind.missingInput,
                'Input is empty',
                entry.key,
                port: port.kind,
              ),
            );
          }
        }
      }
    }
  }

  /// A cabled grant whose source has nothing behind it is not live.
  void _liveGrants() {
    final seen = <String>{};
    for (final cable in cables) {
      final kind = cable.fromKind;
      if (kind == null) {
        continue;
      }
      final spec = kitPortSpecOf(kind);
      final prop = spec.liveProp;
      if (prop == null || !seen.add(cable.sourceId)) {
        continue;
      }
      final frame = document.objectById(cable.sourceId);
      final value = frame?.props[prop]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        continue;
      }
      drafts.add(
        _Draft(
          BoardIssueKind.missingGrant,
          spec.liveMessage ?? '${spec.label} is not live',
          cable.sourceId,
          port: kind,
          cableId: cable.id,
        ),
      );
    }
  }

  final _cycleBodies = <_Draft, Set<String>>{};

  /// LLM replies that feed each other have no first value. Visual loops
  /// through Text or Conversation kits are fine.
  void _replyLoops() {
    final llmInputs = {
      for (final spec in llmKitPorts)
        if (!spec.isOutput && spec.takes(PortValue.reply)) spec.kind,
    };
    final edges = <SceneCable>[
      for (final cable in cables)
        if (cable.fromKind == KitPortKind.llmOutput &&
            llmInputs.contains(cable.toKind) &&
            cable.fromPeerId != null &&
            cable.toPeerId != null)
          cable,
    ];
    final next = <String, Set<String>>{};
    for (final edge in edges) {
      next.putIfAbsent(edge.fromPeerId!, () => {}).add(edge.toPeerId!);
    }
    for (final component in _stronglyConnected(next)) {
      final self =
          component.length == 1 &&
          (next[component.first]?.contains(component.first) ?? false);
      if (component.length < 2 && !self) {
        continue;
      }
      final loop = [
        for (final edge in edges)
          if (component.contains(edge.fromPeerId) &&
              component.contains(edge.toPeerId))
            edge,
      ];
      final names = [
        for (final body in component) _bodyName(body),
        _bodyName(component.first),
      ];
      final message = 'Reply loop: ${names.join(' → ')}';
      for (final edge in loop) {
        marked.add(
          MarkedCable(
            cable: edge,
            kind: BoardIssueKind.cycle,
            message: message,
          ),
        );
      }
      final draft = _Draft(
        BoardIssueKind.cycle,
        message,
        loop.first.sourceId,
        cableId: loop.first.id,
      );
      drafts.add(draft);
      _cycleBodies[draft] = component.toSet();
    }
  }

  String _bodyName(String bodyId) {
    final frame = kitFrameForSelection(document: document, selectedId: bodyId);
    return frame == null ? bodyId : kitDisplayName(document, frame);
  }

  /// Every LLM body the issue's kit feeds, stopping at the first LLM on each
  /// path. A wrong-type link also blocks the kit at its far end.
  Set<String> _affectedLlms(_Draft draft) {
    final bodies = <String>{};
    final visited = <String>{};
    final queue = [draft.frameId, ?_alsoBlocks[draft]];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (!visited.add(current)) {
        continue;
      }
      final frame = document.objectById(current);
      if (frame != null && isLlmKitObject(frame)) {
        for (final port in byFrame[current] ?? const <KitPort>[]) {
          if (port.spec.peer == PortPeer.body) {
            bodies.add(port.peerId);
            break;
          }
        }
        continue;
      }
      for (final cable in cables) {
        if (cable.sourceId == current) {
          queue.add(cable.targetFrameId);
        }
      }
    }
    return bodies;
  }
}

/// Tarjan's components, in discovery order.
List<List<String>> _stronglyConnected(Map<String, Set<String>> next) {
  var counter = 0;
  final index = <String, int>{};
  final low = <String, int>{};
  final stack = <String>[];
  final onStack = <String>{};
  final components = <List<String>>[];

  void visit(String node) {
    index[node] = counter;
    low[node] = counter;
    counter++;
    stack.add(node);
    onStack.add(node);
    for (final to in next[node] ?? const <String>{}) {
      if (!index.containsKey(to)) {
        visit(to);
        low[node] = low[node]! < low[to]! ? low[node]! : low[to]!;
      } else if (onStack.contains(to)) {
        low[node] = low[node]! < index[to]! ? low[node]! : index[to]!;
      }
    }
    if (low[node] == index[node]) {
      final component = <String>[];
      String popped;
      do {
        popped = stack.removeLast();
        onStack.remove(popped);
        component.add(popped);
      } while (popped != node);
      components.add(component.reversed.toList());
    }
  }

  for (final node in next.keys) {
    if (!index.containsKey(node)) {
      visit(node);
    }
  }
  return components;
}
