import 'dart:ui';

import 'package:skapie/kit_api/kit_package_store.dart';
import 'package:skapie/registry/registry.dart';
import 'package:skapie/scene/scene.dart';
import 'package:skapie/tools/patch/patch_board.dart';
import 'package:skapie/tools/check/check_board.dart';
import 'package:skapie/tools/world/kits.dart';

const String demoNoteCardKitId = 'demo.note-card';
const String boardTextKitId = 'board.text';

/// Header, two preview lines, a short gap, and the In / Out row.
const double textFrameHeight = 120;
const String boardBoxKitId = 'board.box';
const String boardButtonKitId = 'board.button';
const String harnessLlmKitId = 'harness.llm';
const String harnessConversationKitId = 'harness.conversation';
const String codingRepositoryKitId = 'coding.repository';
const String proposePatchToolName = 'propose_patch';
const String proposePatchKitId = 'tools.propose_patch';
const String codingPatchProposalKitId = 'coding.patch_proposal';
const String codingReviewDecisionKitId = 'coding.review_decision';
const String codingApplyPatchKitId = 'coding.apply_patch';
const String codingWriteScopeKitId = 'coding.write_scope';
const String codingCheckSpecKitId = 'coding.check_spec';
const String codingRunCheckKitId = 'coding.run_check';
const String codingCheckResultKitId = 'coding.check_result';
const String checkPresetProp = 'checkPreset';
const String checkSpecPort = 'checkSpec';
const String checkWritePort = 'checkWrite';
const String checkResultPort = 'checkResult';
const String writeScopePathProp = 'writeScopePath';
const String writeScopePort = 'writeScope';
const String proposalIdProp = 'proposalId';
const String proposalFingerprintProp = 'fingerprint';
const String reviewDecisionProp = 'decision';
const String patchProposalPort = 'proposal';
const String patchReviewPort = 'review';
const String patchApplyPort = 'apply';
const double proposePatchFrameHeight = 120;
const String harnessSystemPromptKitId = 'harness.system-prompt';
const String harnessToolsKitId = 'harness.tools';
const String skapieKitProp = 'skapieKit';
const String skapieRoleProp = 'skapieRole';
const String attachedToProp = 'attachedTo';
const String connectedToProp = 'connectedTo';
const String connectedPortProp = 'connectedPort';
const String outputToProp = 'outputTo';
const String outputPortProp = 'outputPort';
const String linksProp = 'links';
const String llmInputPort = 'input';
const String llmContextPort = 'context';
const String llmConversationPort = 'conversation';
const String llmToolsPort = 'tools';

/// LLM output cabled into a text kit. The text kit receives the reply.
const String llmTextOutPort = 'text';

/// When a tool kit was last invoked, as an ISO-8601 timestamp.
const String toolLastUsedProp = 'lastUsedAt';
const String repositoryPort = 'repository';
const String repositoryPathProp = 'repositoryPath';
const String kitNameProp = 'name';
const String kitAccentProp = 'accent';
const double kitRadius = 8;
const String harnessToolsRoster =
    'list_kits, get_kit, instantiate_kit, add_object, remove_object, update_frame, update_props, set_locked, save_kit, reload_packages, register_kit';

Size defaultObjectSize(String typeId) {
  return switch (typeId) {
    boxTypeId => const Size(160, 100),
    textTypeId => const Size(220, 48),
    buttonTypeId => const Size(140, 40),
    debugRectType => const Size(120, 80),
    _ => const Size(120, 80),
  };
}

class KitObjectSpec {
  const KitObjectSpec({
    required this.typeId,
    required this.x,
    required this.y,
    this.width,
    this.height,
    this.props = const {},
  });

  final String typeId;
  final double x;
  final double y;
  final double? width;
  final double? height;
  final Map<String, Object?> props;
}

class KitRecipe {
  const KitRecipe({
    required this.id,
    required this.displayName,
    required this.objects,
  });

  final String id;
  final String displayName;
  final List<KitObjectSpec> objects;
}

const KitRecipe boardTextRecipe = KitRecipe(
  id: boardTextKitId,
  displayName: 'Text',
  objects: [
    KitObjectSpec(
      typeId: boxTypeId,
      x: 0,
      y: 0,
      width: 280,
      height: textFrameHeight,
      props: {skapieKitProp: boardTextKitId, skapieRoleProp: 'frame'},
    ),
    KitObjectSpec(
      typeId: textTypeId,
      x: 12,
      y: 40,
      width: 256,
      height: 48,
      props: {
        'content': 'Text',
        'fontSize': 16,
        skapieKitProp: boardTextKitId,
        skapieRoleProp: 'body',
      },
    ),
  ],
);

const KitRecipe boardBoxRecipe = KitRecipe(
  id: boardBoxKitId,
  displayName: 'Box',
  objects: [
    KitObjectSpec(
      typeId: boxTypeId,
      x: 0,
      y: 0,
      width: 200,
      height: 120,
      props: {skapieKitProp: boardBoxKitId, skapieRoleProp: 'frame'},
    ),
  ],
);

const KitRecipe boardButtonRecipe = KitRecipe(
  id: boardButtonKitId,
  displayName: 'Button',
  objects: [
    KitObjectSpec(
      typeId: boxTypeId,
      x: 0,
      y: 0,
      width: 220,
      height: 120,
      props: {skapieKitProp: boardButtonKitId, skapieRoleProp: 'frame'},
    ),
    KitObjectSpec(
      typeId: textTypeId,
      x: 12,
      y: 48,
      width: 196,
      height: 56,
      props: {
        'content': 'Button',
        'fontSize': 16,
        skapieKitProp: boardButtonKitId,
        skapieRoleProp: 'body',
      },
    ),
  ],
);

const KitRecipe demoNoteCardRecipe = KitRecipe(
  id: demoNoteCardKitId,
  displayName: 'Note card',
  objects: [
    KitObjectSpec(typeId: boxTypeId, x: 0, y: 0, width: 200, height: 88),
    KitObjectSpec(
      typeId: textTypeId,
      x: 12,
      y: 16,
      width: 176,
      height: 56,
      props: {'content': 'Note'},
    ),
  ],
);

const KitRecipe harnessLlmRecipe = KitRecipe(
  id: harnessLlmKitId,
  displayName: 'LLM',
  objects: [
    KitObjectSpec(
      typeId: boxTypeId,
      x: 0,
      y: 0,
      width: 320,
      height: 200,
      props: {skapieKitProp: harnessLlmKitId, skapieRoleProp: 'frame'},
    ),
    KitObjectSpec(
      typeId: textTypeId,
      x: 12,
      y: 12,
      width: 296,
      height: 176,
      props: {
        'content': 'Input\n\nOutput\n\nTools: none',
        'fontSize': 14,
        'prompt': '',
        'reply': '',
        'error': '',
        'model': '',
        'provider': '',
        'surface': '',
        skapieKitProp: harnessLlmKitId,
        skapieRoleProp: 'body',
      },
    ),
  ],
);

const KitRecipe harnessConversationRecipe = KitRecipe(
  id: harnessConversationKitId,
  displayName: 'Conversation',
  objects: [
    KitObjectSpec(
      typeId: boxTypeId,
      x: 0,
      y: 0,
      width: 280,
      height: textFrameHeight,
      props: {skapieKitProp: harnessConversationKitId, skapieRoleProp: 'frame'},
    ),
    KitObjectSpec(
      typeId: textTypeId,
      x: 12,
      y: 40,
      width: 256,
      height: 48,
      props: {
        'content': '',
        'fontSize': 13,
        'turns': <Object?>[],
        skapieKitProp: harnessConversationKitId,
        skapieRoleProp: 'body',
      },
    ),
  ],
);

const KitRecipe codingRepositoryRecipe = KitRecipe(
  id: codingRepositoryKitId,
  displayName: 'Repository',
  objects: [
    KitObjectSpec(
      typeId: boxTypeId,
      x: 0,
      y: 0,
      width: 280,
      height: 130,
      props: {
        skapieKitProp: codingRepositoryKitId,
        skapieRoleProp: 'frame',
        repositoryPathProp: '',
      },
    ),
    KitObjectSpec(
      typeId: textTypeId,
      x: 12,
      y: 44,
      width: 256,
      height: 56,
      props: {
        'content': 'Choose a repository in the inspector',
        'fontSize': 13,
        skapieKitProp: codingRepositoryKitId,
        skapieRoleProp: 'body',
      },
    ),
  ],
);

const KitRecipe harnessSystemPromptRecipe = KitRecipe(
  id: harnessSystemPromptKitId,
  displayName: 'System prompt',
  objects: [
    KitObjectSpec(
      typeId: boxTypeId,
      x: 0,
      y: 0,
      width: 280,
      height: 140,
      props: {skapieKitProp: harnessSystemPromptKitId, skapieRoleProp: 'frame'},
    ),
    KitObjectSpec(
      typeId: textTypeId,
      x: 12,
      y: 16,
      width: 256,
      height: 108,
      props: {
        'content': 'System prompt',
        'fontSize': 14,
        attachedToProp: '',
        skapieKitProp: harnessSystemPromptKitId,
        skapieRoleProp: 'prompt',
      },
    ),
  ],
);

const KitRecipe harnessToolsRecipe = KitRecipe(
  id: harnessToolsKitId,
  displayName: 'Tools',
  objects: [
    KitObjectSpec(
      typeId: boxTypeId,
      x: 0,
      y: 0,
      width: 280,
      height: 180,
      props: {skapieKitProp: harnessToolsKitId, skapieRoleProp: 'frame'},
    ),
    KitObjectSpec(
      typeId: textTypeId,
      x: 12,
      y: 16,
      width: 256,
      height: 148,
      props: {
        'content': 'Kit tools (stub)\n\n$harnessToolsRoster',
        'fontSize': 14,
        'toolNames': harnessToolsRoster,
        attachedToProp: '',
        skapieKitProp: harnessToolsKitId,
        skapieRoleProp: 'tools',
      },
    ),
  ],
);

/// High-level scene mutations. Always wraps [SceneStore.apply].
///
/// [registerKit] is ephemeral (in-memory kit recipe). Saved kit packages under `kits/` are
/// the durable shelf; [reloadPackages] loads them and **disk replaces memory**.
class KitApi {
  KitApi({required this.store, required this.registry, this.packages});

  final SceneStore store;
  final ObjectRegistry registry;
  final KitPackageStore? packages;
  void Function(String message)? log;
  final Map<String, KitRecipe> _kits = {};

  String addObject({
    required String typeId,
    double x = 0,
    double y = 0,
    double? width,
    double? height,
    Map<String, Object?> props = const {},
  }) {
    final type = registry.get(typeId);
    if (type == null) {
      throw ArgumentError('Unknown typeId: $typeId');
    }
    final size = defaultObjectSize(typeId);
    final merged = Map<String, Object?>.of(type.defaultProps)..addAll(props);
    final kitId = props[skapieKitProp]?.toString().trim() ?? '';
    if (kitId.isNotEmpty) {
      if (typeId == boxTypeId) {
        if (!props.containsKey('fill')) {
          merged.remove('fill');
        }
        if (!props.containsKey('cornerRadius')) {
          merged['cornerRadius'] = kitRadius;
        }
      }
      if (typeId == textTypeId && !props.containsKey('color')) {
        merged.remove('color');
      }
    }
    final id = newSceneId('o');
    store.apply(
      AddObject(
        SceneObject(
          id: id,
          type: typeId,
          x: x,
          y: y,
          width: width ?? size.width,
          height: height ?? size.height,
          props: Map<String, Object?>.unmodifiable(merged),
        ),
      ),
    );
    return id;
  }

  void removeObject(String id) {
    store.apply(RemoveObject(id));
  }

  void updateFrame({
    required String id,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
  }) {
    store.apply(
      UpdateObjectFrame(
        id: id,
        x: x,
        y: y,
        width: width,
        height: height,
        rotation: rotation,
      ),
    );
  }

  void updateProps(String id, Map<String, Object?> patch) {
    store.apply(UpdateObjectProps(id, patch));
  }

  void setLocked(String id, bool locked) {
    store.apply(SetObjectLocked(id: id, locked: locked));
  }

  /// Patch several objects as one undo step.
  void updatePropsMany(Map<String, Map<String, Object?>> patches) {
    store.apply(
      SceneBatch([
        for (final entry in patches.entries)
          UpdateObjectProps(entry.key, entry.value),
      ]),
    );
  }

  /// Remove several objects as one undo step.
  void removeObjects(List<String> ids) {
    store.apply(SceneBatch([for (final id in ids) RemoveObject(id)]));
  }

  void registerKit(KitRecipe recipe) {
    if (_kits.containsKey(recipe.id)) {
      throw StateError('Duplicate kit id: ${recipe.id}');
    }
    _kits[recipe.id] = recipe;
  }

  KitRecipe? getKit(String kitId) => _kits[kitId];

  List<KitRecipe> listKits() => List.unmodifiable(_kits.values);

  /// Scan the kits root and register each package. Disk replaces in-memory
  /// kit recipes with the same id.
  Future<void> reloadPackages() async {
    final store = packages;
    if (store == null) {
      return;
    }
    final loaded = await store.loadAll();
    for (final warning in loaded.warnings) {
      log?.call(warning);
    }
    for (final error in loaded.errors) {
      log?.call(error);
    }
    for (final recipe in loaded.recipes) {
      if (_kits.containsKey(recipe.id)) {
        log?.call('Disk package ${recipe.id} replaces in-memory kit recipe');
      }
      _kits[recipe.id] = recipe;
    }
    log?.call(
      'Loaded ${loaded.recipes.length} kit package(s) from ${store.root.absolute.path}',
    );
  }

  /// Write `kits/<id>/kit.json`, then register/update the in-memory kit recipe.
  Future<void> saveKit(KitRecipe recipe) async {
    final store = packages;
    if (store == null) {
      throw StateError('No kit package store');
    }
    await store.write(recipe);
    _kits[recipe.id] = recipe;
  }

  /// Validate every spec type, then apply. N objects = N undo steps.
  List<String> instantiate(String kitId, {required Offset origin}) {
    final recipe = _kits[kitId];
    if (recipe == null) {
      throw ArgumentError('Unknown kit: $kitId');
    }
    for (final spec in recipe.objects) {
      if (registry.get(spec.typeId) == null) {
        throw ArgumentError('Unknown typeId: ${spec.typeId}');
      }
    }
    final name = nextKitName(
      store.document,
      stem: recipe.id.startsWith('tools.') ? 'Tool' : recipe.displayName,
      kitId: recipe.id,
    );
    return [
      for (final spec in recipe.objects)
        addObject(
          typeId: spec.typeId,
          x: origin.dx + spec.x,
          y: origin.dy + spec.y,
          width: spec.width,
          height: spec.height,
          props: {...spec.props, kitNameProp: name},
        ),
    ];
  }
}

/// First kit of a kind is [stem]. The next free name is `stem (2)`, then `(3)`.
String nextKitName(
  SceneDocument document, {
  required String stem,
  required String kitId,
}) {
  final names = <String>{};
  var unnamed = 0;
  for (final object in document.objects) {
    if (object.props[skapieRoleProp] != 'frame') {
      continue;
    }
    if (object.props[skapieKitProp]?.toString() != kitId) {
      continue;
    }
    final name = object.props[kitNameProp]?.toString().trim() ?? '';
    if (name.isEmpty) {
      unnamed++;
    } else {
      names.add(name);
    }
  }
  var slot = 0;
  while (true) {
    final candidate = slot == 0 ? stem : '$stem (${slot + 1})';
    final heldByUnnamed = slot < unnamed;
    if (!heldByUnnamed && !names.contains(candidate)) {
      return candidate;
    }
    slot++;
  }
}

String kitNameStem(String kitId) {
  if (kitId == harnessLlmKitId) {
    return 'LLM';
  }
  if (kitId == harnessSystemPromptKitId) {
    return 'System prompt';
  }
  if (kitId == boardTextKitId) {
    return 'Text';
  }
  if (kitId == boardBoxKitId) {
    return 'Box';
  }
  if (kitId == boardButtonKitId) {
    return 'Button';
  }
  if (kitId.startsWith('tools.')) {
    return 'Tool';
  }
  if (kitId == codingRepositoryKitId) {
    return 'Repository';
  }
  if (kitId == codingPatchProposalKitId) {
    return 'Patch Proposal';
  }
  if (kitId == codingReviewDecisionKitId) {
    return 'Review Decision';
  }
  if (kitId == codingApplyPatchKitId) {
    return 'Apply Patch';
  }
  if (kitId == codingWriteScopeKitId) {
    return 'Write Scope';
  }
  if (kitId.startsWith('harness.')) {
    return kitId.substring('harness.'.length);
  }
  return kitId;
}

/// The one identity shown for a kit. Explicit [kitNameProp] wins.
String kitDisplayName(SceneDocument document, SceneObject object) {
  final frame = _nameFrame(document, object);
  final explicit = frame.props[kitNameProp]?.toString().trim() ?? '';
  if (explicit.isNotEmpty) {
    return explicit;
  }
  final kitId = frame.props[skapieKitProp]?.toString().trim() ?? '';
  if (kitId.isEmpty) {
    return frame.id;
  }
  final stem = kitNameStem(kitId);
  final frames = [
    for (final item in document.objects)
      if (item.props[skapieRoleProp] == 'frame' &&
          item.props[skapieKitProp]?.toString() == kitId)
        item,
  ];
  final taken = <String>{
    for (final item in document.objects)
      if ((item.props[kitNameProp]?.toString().trim() ?? '').isNotEmpty)
        item.props[kitNameProp].toString().trim(),
  };
  var slot = 0;
  for (final item in frames) {
    final named = item.props[kitNameProp]?.toString().trim() ?? '';
    if (named.isNotEmpty) {
      continue;
    }
    var candidate = slot == 0 ? stem : '$stem (${slot + 1})';
    while (taken.contains(candidate)) {
      slot++;
      candidate = slot == 0 ? stem : '$stem (${slot + 1})';
    }
    if (item.id == frame.id) {
      return candidate;
    }
    taken.add(candidate);
    slot++;
  }
  return stem;
}

SceneObject _nameFrame(SceneDocument document, SceneObject object) {
  if (object.props[skapieRoleProp] == 'frame') {
    return object;
  }
  final kitId = object.props[skapieKitProp]?.toString().trim() ?? '';
  if (kitId.isEmpty) {
    return object;
  }
  for (final item in document.objects) {
    if (item.props[skapieRoleProp] != 'frame') {
      continue;
    }
    if (item.props[skapieKitProp]?.toString() != kitId) {
      continue;
    }
    final inside =
        object.x >= item.x - 0.5 &&
        object.y >= item.y - 0.5 &&
        object.x + object.width <= item.x + item.width + 0.5 &&
        object.y + object.height <= item.y + item.height + 0.5;
    if (inside) {
      return item;
    }
  }
  return object;
}

KitApi createAppKitApi({
  required SceneStore store,
  ObjectRegistry? registry,
  KitPackageStore? packages,
}) {
  final api = KitApi(
    store: store,
    registry: registry ?? createBuiltinRegistry(),
    packages: packages,
  );
  api.registerKit(demoNoteCardRecipe);
  api.registerKit(boardTextRecipe);
  api.registerKit(boardBoxRecipe);
  api.registerKit(boardButtonRecipe);
  api.registerKit(harnessLlmRecipe);
  api.registerKit(harnessConversationRecipe);
  api.registerKit(codingRepositoryRecipe);
  api.registerKit(harnessSystemPromptRecipe);
  api.registerKit(harnessToolsRecipe);
  registerWorldToolKits(api);
  registerPatchKits(api);
  registerCheckKits(api);
  return api;
}
