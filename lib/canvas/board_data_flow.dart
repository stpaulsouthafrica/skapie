import 'package:skapie/scene/scene.dart';

/// A route that was actually used by a board value or an explicit effect.
/// Cable ids are ordered from the source to the receiver.
class BoardDataRoute {
  const BoardDataRoute(
    this.cableIds,
    this.frameIds, {
    this.how = 'Value delivered',
  });

  final List<String> cableIds;
  final List<String> frameIds;
  final String how;
}

class BoardCableUse {
  const BoardCableUse(this.at, this.how);

  final DateTime at;
  final String how;
}

class BoardDataEvent {
  const BoardDataEvent(this.sequence, this.route);

  final int sequence;
  final BoardDataRoute route;
}

/// Layout edits and connection changes do not create pulses.
List<BoardDataRoute> boardDataRoutesForChange(
  SceneDocument _,
  SceneDocument _,
) {
  return const [];
}
