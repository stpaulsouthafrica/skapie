import 'package:skapie/canvas/kit_ports.dart';
import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/registry/builtin_types.dart';
import 'package:skapie/tools/check/check_board.dart';
import 'package:skapie/tools/patch/patch_board.dart';

/// Demoted kit recipes. These are not part of the default install. They stay in
/// host code only as rebuild references (see docs/phase_12_rebuild_notes.md), so
/// a test or a user researching the old flow can opt in with
/// [registerDemotedKits]. The matching packages live under examples/kits/.
class DemotedToolKitSpec {
  const DemotedToolKitSpec(
    this.toolName,
    this.description, {
    this.requiresRepository = false,
    this.displayName,
    this.frameHeight,
  });

  final String toolName;
  final String description;
  final bool requiresRepository;
  final String? displayName;
  final double? frameHeight;

  String get label => displayName ?? toolName;
  double get height => frameHeight ?? toolFrameHeight;
}

const List<DemotedToolKitSpec> demotedToolKitSpecs = [
  DemotedToolKitSpec('list_kits', 'List registered kits.'),
  DemotedToolKitSpec('get_kit', 'Get one kit recipe by id.'),
  DemotedToolKitSpec('instantiate_kit', 'Instantiate a kit into the scene.'),
  DemotedToolKitSpec('add_object', 'Add one scene object.'),
  DemotedToolKitSpec('remove_object', 'Remove a scene object by id.'),
  DemotedToolKitSpec('update_frame', 'Patch a scene object frame.'),
  DemotedToolKitSpec(
    'update_props',
    'Shallow-merge props. Null values remove keys.',
  ),
  DemotedToolKitSpec('set_locked', 'Set SceneObject.locked.'),
  DemotedToolKitSpec('save_kit', 'Write a kit package to disk and register it.'),
  DemotedToolKitSpec('reload_packages', 'Reload kit packages from disk.'),
  DemotedToolKitSpec('register_kit', 'Register an ephemeral in-memory kit.'),
  DemotedToolKitSpec(
    'repo_list_files',
    'List source files in the connected repository.',
    requiresRepository: true,
  ),
  DemotedToolKitSpec(
    'repo_search_text',
    'Search text in the connected repository.',
    requiresRepository: true,
  ),
  DemotedToolKitSpec(
    'repo_read_file',
    'Read a bounded range of a repository file.',
    requiresRepository: true,
  ),
  DemotedToolKitSpec(
    'repo_git_status',
    'Read Git branch and working tree status.',
    requiresRepository: true,
  ),
  DemotedToolKitSpec(
    'repo_git_diff',
    'Read a bounded Git diff.',
    requiresRepository: true,
  ),
  DemotedToolKitSpec(
    proposePatchToolName,
    'Propose one exact text replacement in an existing file. Does not write.',
    displayName: 'Propose Patch',
    frameHeight: proposePatchFrameHeight,
    requiresRepository: true,
  ),
];

String demotedToolKitId(String toolName) => 'tools.$toolName';

KitRecipe demotedToolKitRecipe(DemotedToolKitSpec spec) {
  final id = demotedToolKitId(spec.toolName);
  Map<String, Object?> grantProps() =>
      {if (spec.requiresRepository) 'requiresRepository': true};
  return KitRecipe(
    id: id,
    displayName: spec.label,
    objects: [
      KitObjectSpec(
        typeId: boxTypeId,
        x: 0,
        y: 0,
        width: 200,
        height: spec.height,
        props: {
          skapieKitProp: id,
          skapieRoleProp: 'frame',
          'description': spec.description,
          ...grantProps(),
        },
      ),
      KitObjectSpec(
        typeId: textTypeId,
        x: 12,
        y: 36,
        width: 176,
        height: 20,
        props: {
          'content': spec.toolName,
          'fontSize': 14,
          'toolName': spec.toolName,
          attachedToProp: '',
          ...grantProps(),
          skapieKitProp: id,
          skapieRoleProp: 'grant',
        },
      ),
    ],
  );
}

/// Register every demoted kit into [kitApi]. Off by default.
void registerDemotedKits(KitApi kitApi) {
  for (final spec in demotedToolKitSpecs) {
    kitApi.registerKit(demotedToolKitRecipe(spec));
  }
  kitApi.registerKit(harnessRunControlRecipe);
  kitApi.registerKit(harnessSystemPromptRecipe);
  kitApi.registerKit(harnessToolsRecipe);
  registerPatchKits(kitApi);
  registerCheckKits(kitApi);
}
