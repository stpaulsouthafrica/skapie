import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/attach.dart';

/// Internal handle for one built-in port. Descriptors below say what it does.
enum KitPortKind {
  textIn,
  textOut,
  toolOut,
  conversationIn,
  conversationOut,
  repositoryOut,
  toolRepository,
  llmInput,
  llmContext,
  llmConversation,
  llmTools,
  llmOutput,
}

enum PortDirection { input, output }

/// What a cable carries. An output carries one value; an input lists the
/// values it takes.
enum PortValue { text, reply, conversation, transcript, tool, repository }

enum PortMultiplicity { one, many }

/// Which object a cable end names: the kit frame, or the kit's body.
enum PortPeer { frame, body }

/// Which end of a connection stores the scene link.
enum PortLinkOwner { source, target }

enum PortSide { left, right }

/// Built-in anchors. `footer` is the bottom In / Out row, `middle` is centered
/// under the title, `row` is one of the LLM's stacked port rows.
enum PortAnchor { footer, middle, row }

class PortPlacement {
  const PortPlacement.footer(this.side) : anchor = PortAnchor.footer, row = 0;
  const PortPlacement.middle(this.side) : anchor = PortAnchor.middle, row = 0;
  const PortPlacement.row(this.row, this.side) : anchor = PortAnchor.row;

  final PortAnchor anchor;
  final PortSide side;
  final int row;
}

class KitPortSpec {
  const KitPortSpec({
    required this.id,
    required this.kind,
    required this.label,
    required this.direction,
    required this.value,
    required this.placement,
    this.accepts = const {},
    this.multiplicity = PortMultiplicity.many,
    this.peer = PortPeer.frame,
    this.linkPort,
    this.linkOwner = PortLinkOwner.source,
    this.affectsRun = true,
    this.requiresProp,
  });

  /// Stable endpoint id within the kit.
  final String id;
  final KitPortKind kind;
  final String label;
  final PortDirection direction;
  final PortValue value;
  final PortPlacement placement;

  /// Inputs only. Empty means just [value].
  final Set<PortValue> accepts;
  final PortMultiplicity multiplicity;
  final PortPeer peer;

  /// Inputs only. The `port` written into scene links, when it predates [id].
  final String? linkPort;
  final PortLinkOwner linkOwner;
  final bool affectsRun;

  /// The port exists only while this frame prop is `true`.
  final String? requiresProp;

  bool get isOutput => direction == PortDirection.output;
  String get storedPort => linkPort ?? id;

  bool takes(PortValue incoming) {
    return (accepts.isEmpty ? {value} : accepts).contains(incoming);
  }
}

const List<KitPortSpec> textKitPorts = [
  KitPortSpec(
    id: 'in',
    kind: KitPortKind.textIn,
    label: 'In',
    direction: PortDirection.input,
    value: PortValue.reply,
    placement: PortPlacement.footer(PortSide.left),
    linkPort: llmTextOutPort,
    affectsRun: false,
  ),
  KitPortSpec(
    id: 'out',
    kind: KitPortKind.textOut,
    label: 'Out',
    direction: PortDirection.output,
    value: PortValue.text,
    placement: PortPlacement.footer(PortSide.right),
  ),
];

const List<KitPortSpec> conversationKitPorts = [
  KitPortSpec(
    id: 'in',
    kind: KitPortKind.conversationIn,
    label: 'In',
    direction: PortDirection.input,
    value: PortValue.conversation,
    placement: PortPlacement.footer(PortSide.left),
    linkPort: llmConversationPort,
    linkOwner: PortLinkOwner.target,
  ),
  KitPortSpec(
    id: 'out',
    kind: KitPortKind.conversationOut,
    label: 'Out',
    direction: PortDirection.output,
    value: PortValue.transcript,
    placement: PortPlacement.footer(PortSide.right),
  ),
];

const List<KitPortSpec> repositoryKitPorts = [
  KitPortSpec(
    id: 'out',
    kind: KitPortKind.repositoryOut,
    label: 'Out',
    direction: PortDirection.output,
    value: PortValue.repository,
    placement: PortPlacement.footer(PortSide.right),
  ),
];

const List<KitPortSpec> worldToolKitPorts = [
  KitPortSpec(
    id: repositoryPort,
    kind: KitPortKind.toolRepository,
    label: 'Repository',
    direction: PortDirection.input,
    value: PortValue.repository,
    placement: PortPlacement.middle(PortSide.left),
    multiplicity: PortMultiplicity.one,
    requiresProp: 'requiresRepository',
  ),
  KitPortSpec(
    id: 'out',
    kind: KitPortKind.toolOut,
    label: 'LLM',
    direction: PortDirection.output,
    value: PortValue.tool,
    placement: PortPlacement.middle(PortSide.right),
  ),
];

const List<KitPortSpec> llmKitPorts = [
  KitPortSpec(
    id: llmInputPort,
    kind: KitPortKind.llmInput,
    label: 'Input',
    direction: PortDirection.input,
    value: PortValue.text,
    accepts: {PortValue.text, PortValue.reply},
    placement: PortPlacement.row(0, PortSide.left),
    peer: PortPeer.body,
  ),
  KitPortSpec(
    id: llmContextPort,
    kind: KitPortKind.llmContext,
    label: 'Context',
    direction: PortDirection.input,
    value: PortValue.text,
    accepts: {PortValue.text, PortValue.reply},
    placement: PortPlacement.row(1, PortSide.left),
    peer: PortPeer.body,
  ),
  KitPortSpec(
    id: llmToolsPort,
    kind: KitPortKind.llmTools,
    label: 'Tools',
    direction: PortDirection.input,
    value: PortValue.tool,
    placement: PortPlacement.row(2, PortSide.left),
    peer: PortPeer.body,
  ),
  KitPortSpec(
    id: llmConversationPort,
    kind: KitPortKind.llmConversation,
    label: 'Conversation',
    direction: PortDirection.output,
    value: PortValue.conversation,
    placement: PortPlacement.row(3, PortSide.right),
    peer: PortPeer.body,
  ),
  KitPortSpec(
    id: 'output',
    kind: KitPortKind.llmOutput,
    label: 'Output',
    direction: PortDirection.output,
    value: PortValue.reply,
    placement: PortPlacement.row(4, PortSide.right),
    peer: PortPeer.body,
  ),
];

/// Built-in kits and their ports. World tool kits share [worldToolKitPorts].
const Map<String, List<KitPortSpec>> builtinKitPorts = {
  boardTextKitId: textKitPorts,
  harnessConversationKitId: conversationKitPorts,
  codingRepositoryKitId: repositoryKitPorts,
  harnessLlmKitId: llmKitPorts,
};

final Map<KitPortKind, KitPortSpec> _specsByKind = {
  for (final specs in [...builtinKitPorts.values, worldToolKitPorts])
    for (final spec in specs) spec.kind: spec,
};

KitPortSpec kitPortSpecOf(KitPortKind kind) => _specsByKind[kind]!;

/// Ports this kit frame shows right now.
List<KitPortSpec> kitPortSpecsFor(SceneObject frame) {
  final kitId = kitIdOf(frame);
  if (kitId == null) {
    return const [];
  }
  final specs =
      builtinKitPorts[kitId] ??
      (isWorldToolKit(frame) ? worldToolKitPorts : const <KitPortSpec>[]);
  return [
    for (final spec in specs)
      if (spec.requiresProp == null || frame.props[spec.requiresProp] == true)
        spec,
  ];
}
