import 'package:skapie/kit_api/kit_api.dart';

/// The four starter tools. A tool kit not in this set is a user package and is
/// hidden from the default palette.
const Set<String> starterToolKitIds = {
  'tools.read',
  'tools.write',
  'tools.edit',
  'tools.shell',
};

/// The default install. These cards make up the starter board and the default
/// palette. Everything else lives under examples/ and is user-installed. This
/// is the one place the default experience is defined.
const Set<String> starterKitIds = {
  boardTextKitId,
  boardBoxKitId,
  boardButtonKitId,
  harnessLlmKitId,
  harnessConversationKitId,
  codingRepositoryKitId,
  skapieExtensionsKitId,
  ...starterToolKitIds,
};
