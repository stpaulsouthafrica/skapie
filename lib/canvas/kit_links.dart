import 'package:skapie/kit_api/kit_api.dart';
import 'package:skapie/kit_api/kit_compound.dart';
import 'package:skapie/scene/scene.dart';

class KitLink {
  const KitLink({required this.to, required this.port});

  final String to;
  final String port;

  String get id => '$to|$port';
}

/// Every compatible link on this object. A missing [linksProp] still reads the
/// older single-target props.
List<KitLink> kitLinksOf(SceneObject object) {
  if (object.props.containsKey(linksProp)) {
    return _parseLinks(object.props[linksProp]);
  }
  final connected = object.props[connectedToProp]?.toString().trim() ?? '';
  if (connected.isNotEmpty) {
    final port = object.props[connectedPortProp]?.toString().trim() ?? '';
    return [
      KitLink(
        to: connected,
        port: port == llmContextPort ? llmContextPort : llmInputPort,
      ),
    ];
  }
  final attached = object.props[attachedToProp]?.toString().trim() ?? '';
  if (attached.isNotEmpty) {
    return [KitLink(to: attached, port: llmToolsPort)];
  }
  final output = object.props[outputToProp]?.toString().trim() ?? '';
  if (output.isNotEmpty) {
    final port = object.props[outputPortProp]?.toString().trim() ?? '';
    return [
      KitLink(
        to: output,
        port: port == llmContextPort ? llmContextPort : llmInputPort,
      ),
    ];
  }
  return const [];
}

bool kitHasLink(
  SceneObject object, {
  required String to,
  required String port,
}) {
  return kitLinksOf(object).any((link) => link.to == to && link.port == port);
}

void addKitLink({
  required KitApi kitApi,
  required String objectId,
  required String to,
  required String port,
}) {
  if (to.isEmpty) {
    return;
  }
  final members = _linkMembers(kitApi, objectId);
  if (members.isEmpty) {
    return;
  }
  final links = _unionLinks(members);
  if (links.any((link) => link.to == to && link.port == port)) {
    return;
  }
  _writeLinks(kitApi, members, [...links, KitLink(to: to, port: port)]);
}

void removeKitLink({
  required KitApi kitApi,
  required String objectId,
  required String to,
  required String port,
}) {
  final members = _linkMembers(kitApi, objectId);
  if (members.isEmpty) {
    return;
  }
  _writeLinks(kitApi, members, [
    for (final link in _unionLinks(members))
      if (!(link.to == to && link.port == port)) link,
  ]);
}

void replaceKitLinks({
  required KitApi kitApi,
  required String objectId,
  required List<KitLink> links,
}) {
  _writeLinks(kitApi, _linkMembers(kitApi, objectId), links);
}

void connectTextToLlm({
  required KitApi kitApi,
  required String textObjectId,
  required String llmBodyId,
  String port = llmInputPort,
}) {
  addKitLink(kitApi: kitApi, objectId: textObjectId, to: llmBodyId, port: port);
}

void disconnectText({
  required KitApi kitApi,
  required String textObjectId,
  String? llmBodyId,
  String? port,
}) {
  if (llmBodyId != null && port != null) {
    removeKitLink(
      kitApi: kitApi,
      objectId: textObjectId,
      to: llmBodyId,
      port: port,
    );
    return;
  }
  replaceKitLinks(kitApi: kitApi, objectId: textObjectId, links: const []);
}

void connectLlmOutput({
  required KitApi kitApi,
  required String sourceBodyId,
  required String targetBodyId,
  String port = llmInputPort,
}) {
  addKitLink(
    kitApi: kitApi,
    objectId: sourceBodyId,
    to: targetBodyId,
    port: port,
  );
}

void disconnectLlmOutput({
  required KitApi kitApi,
  required String sourceBodyId,
  String? targetBodyId,
  String? port,
}) {
  if (targetBodyId != null && port != null) {
    removeKitLink(
      kitApi: kitApi,
      objectId: sourceBodyId,
      to: targetBodyId,
      port: port,
    );
    return;
  }
  replaceKitLinks(kitApi: kitApi, objectId: sourceBodyId, links: const []);
}

List<KitLink> _parseLinks(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  final links = <KitLink>[];
  for (final item in raw) {
    if (item is! Map) {
      continue;
    }
    final to = item['to']?.toString().trim() ?? '';
    final port = item['port']?.toString().trim() ?? '';
    if (to.isEmpty || port.isEmpty) {
      continue;
    }
    if (links.any((link) => link.to == to && link.port == port)) {
      continue;
    }
    links.add(KitLink(to: to, port: port));
  }
  return links;
}

List<SceneObject> _linkMembers(KitApi kitApi, String objectId) {
  return kitMembers(document: kitApi.store.document, selectedId: objectId) ??
      [
        if (kitApi.store.document.objectById(objectId) != null)
          kitApi.store.document.objectById(objectId)!,
      ];
}

List<KitLink> _unionLinks(List<SceneObject> members) {
  final links = <KitLink>[];
  for (final member in members) {
    for (final link in kitLinksOf(member)) {
      if (links.any((item) => item.to == link.to && item.port == link.port)) {
        continue;
      }
      links.add(link);
    }
  }
  return links;
}

void _writeLinks(
  KitApi kitApi,
  List<SceneObject> members,
  List<KitLink> links,
) {
  final props = <String, Object?>{
    linksProp: [
      for (final link in links) {'to': link.to, 'port': link.port},
    ],
    connectedToProp: '',
    connectedPortProp: '',
    attachedToProp: '',
    outputToProp: '',
    outputPortProp: '',
  };
  kitApi.updatePropsMany({for (final member in members) member.id: props});
}
