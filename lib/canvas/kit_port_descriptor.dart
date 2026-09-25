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
  proposalResult,
  proposalIn,
  proposalOut,
  reviewIn,
  reviewOut,
  applyIn,
}

enum PortDirection { input, output }

/// What a cable carries. An output carries one value; an input lists the
/// values it takes.
/// Data flows into a run. A capability is offered to the model. A grant lets
/// a kit act on something outside the board.
enum PortRole {
  data('Data', 'Carries a value into or out of a run.'),
  capability('Capability', 'Offers a tool the model may call.'),
  grant('Grant', 'Lets the tool reach something outside the board.');

  const PortRole(this.label, this.meaning);

  final String label;
  final String meaning;
}

enum PortValue {
  text('Text', PortRole.data),
  reply('Reply', PortRole.data),
  conversation('Conversation', PortRole.data),
  transcript('Transcript', PortRole.data),
  tool('Tool', PortRole.capability),
  repository('Repository', PortRole.grant),
  patchProposal('Proposal', PortRole.data),
  reviewDecision('Review', PortRole.data);

  const PortValue(this.label, this.role);

  final String label;
  final PortRole role;
}

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
    this.requiredGroup,
    this.requiredMessage,
    this.liveProp,
    this.liveMessage,
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

  /// Ports sharing a group need at least one cable between them.
  final String? requiredGroup;
  final String? requiredMessage;

  /// Outputs only. What this port carries is live only while this frame prop
  /// is non-empty.
  final String? liveProp;
  final String? liveMessage;

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
    liveProp: repositoryPathProp,
    liveMessage: 'Repository has no folder',
  ),
];

const KitPortSpec toolOutPort = KitPortSpec(
  id: 'out',
  kind: KitPortKind.toolOut,
  label: 'LLM',
  direction: PortDirection.output,
  value: PortValue.tool,
  placement: PortPlacement.middle(PortSide.right),
);

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
    requiredGroup: repositoryPort,
    requiredMessage: 'Repository grant missing',
  ),
  toolOutPort,
];

const List<KitPortSpec> proposePatchKitPorts = [
  KitPortSpec(
    id: repositoryPort,
    kind: KitPortKind.toolRepository,
    label: 'Repository',
    direction: PortDirection.input,
    value: PortValue.repository,
    placement: PortPlacement.middle(PortSide.left),
    multiplicity: PortMultiplicity.one,
    requiresProp: 'requiresRepository',
    requiredGroup: repositoryPort,
    requiredMessage: 'Repository grant missing',
  ),
  toolOutPort,
  KitPortSpec(
    id: 'result',
    kind: KitPortKind.proposalResult,
    label: 'Result',
    direction: PortDirection.output,
    value: PortValue.patchProposal,
    placement: PortPlacement.footer(PortSide.right),
  ),
];

const List<KitPortSpec> patchProposalKitPorts = [
  KitPortSpec(
    id: patchProposalPort,
    kind: KitPortKind.proposalIn,
    label: 'In',
    direction: PortDirection.input,
    value: PortValue.patchProposal,
    placement: PortPlacement.footer(PortSide.left),
  ),
  KitPortSpec(
    id: 'out',
    kind: KitPortKind.proposalOut,
    label: 'Out',
    direction: PortDirection.output,
    value: PortValue.patchProposal,
    placement: PortPlacement.footer(PortSide.right),
  ),
];

const List<KitPortSpec> reviewDecisionKitPorts = [
  KitPortSpec(
    id: patchReviewPort,
    kind: KitPortKind.reviewIn,
    label: 'In',
    direction: PortDirection.input,
    value: PortValue.patchProposal,
    placement: PortPlacement.footer(PortSide.left),
  ),
  KitPortSpec(
    id: 'out',
    kind: KitPortKind.reviewOut,
    label: 'Out',
    direction: PortDirection.output,
    value: PortValue.reviewDecision,
    placement: PortPlacement.footer(PortSide.right),
  ),
];

const List<KitPortSpec> applyPatchKitPorts = [
  KitPortSpec(
    id: patchApplyPort,
    kind: KitPortKind.applyIn,
    label: 'In',
    direction: PortDirection.input,
    value: PortValue.reviewDecision,
    placement: PortPlacement.footer(PortSide.left),
  ),
];

const String _llmSink = 'sink';
const String _llmSinkMessage = 'Needs Output or Conversation';

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
    requiredGroup: llmInputPort,
    requiredMessage: 'Needs input',
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
    requiredGroup: _llmSink,
    requiredMessage: _llmSinkMessage,
  ),
  KitPortSpec(
    id: 'output',
    kind: KitPortKind.llmOutput,
    label: 'Output',
    direction: PortDirection.output,
    value: PortValue.reply,
    placement: PortPlacement.row(4, PortSide.right),
    peer: PortPeer.body,
    requiredGroup: _llmSink,
    requiredMessage: _llmSinkMessage,
  ),
];

/// Built-in kits and their ports. World tool kits share [worldToolKitPorts].
const Map<String, List<KitPortSpec>> builtinKitPorts = {
  boardTextKitId: textKitPorts,
  harnessConversationKitId: conversationKitPorts,
  codingRepositoryKitId: repositoryKitPorts,
  harnessLlmKitId: llmKitPorts,
  proposePatchKitId: proposePatchKitPorts,
  codingPatchProposalKitId: patchProposalKitPorts,
  codingReviewDecisionKitId: reviewDecisionKitPorts,
  codingApplyPatchKitId: applyPatchKitPorts,
};

final Map<KitPortKind, KitPortSpec> _specsByKind = {
  for (final specs in [...builtinKitPorts.values, worldToolKitPorts])
    for (final spec in specs) spec.kind: spec,
};

KitPortSpec kitPortSpecOf(KitPortKind kind) => _specsByKind[kind]!;

List<KitPortSpec> get allKitPortSpecs => _specsByKind.values.toList();

/// Why [a] and [b] cannot be cabled, or null when they can.
String? kitPortRefusal(KitPortKind a, KitPortKind b) {
  final first = kitPortSpecOf(a);
  final second = kitPortSpecOf(b);
  if (first.isOutput == second.isOutput) {
    return 'Connect an output to an input';
  }
  final output = first.isOutput ? first : second;
  final input = first.isOutput ? second : first;
  if (input.takes(output.value)) {
    return null;
  }
  final takes = (input.accepts.isEmpty ? {input.value} : input.accepts)
      .map((value) => value.label)
      .join(' or ');
  return '${input.label} takes $takes, not ${output.value.label}';
}

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
