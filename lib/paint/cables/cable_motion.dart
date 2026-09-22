import 'package:flutter/material.dart';

/// How a just-made connection should appear on the target kit.
///
/// The link is already stored. This only delays the painted registration
/// until the cable's light arrives, then fades it in.
class CableMotion extends ChangeNotifier {
  final _shown = <String, double>{};
  final _glow = <String, double>{};

  /// 1 when the cable is settled or was already on the board.
  double shown(String? cableId) {
    if (cableId == null) {
      return 1;
    }
    return _shown[cableId] ?? 1;
  }

  double glow(String? cableId) {
    if (cableId == null) {
      return 0;
    }
    return _glow[cableId] ?? 0;
  }

  /// Hide a registration for the frame the cable first appears. No notify,
  /// so a sibling can read it during the same build.
  void hold(String cableId) {
    _shown[cableId] = 0;
    _glow[cableId] = 0;
  }

  void present(String cableId, double shown, double glow) {
    final nextShown = shown.clamp(0.0, 1.0);
    final nextGlow = glow.clamp(0.0, 1.0);
    if (_shown[cableId] == nextShown && _glow[cableId] == nextGlow) {
      return;
    }
    _shown[cableId] = nextShown;
    _glow[cableId] = nextGlow;
    notifyListeners();
  }

  void release(String cableId) {
    if (!_shown.containsKey(cableId) && !_glow.containsKey(cableId)) {
      return;
    }
    _shown.remove(cableId);
    _glow.remove(cableId);
    notifyListeners();
  }
}

TextStyle arrivalTextStyle({
  required TextStyle base,
  required Color glowColor,
  required double shown,
  required double glow,
}) {
  final ink = base.color ?? const Color(0xFFF4EFE6);
  return base.copyWith(
    color: ink.withValues(alpha: shown.clamp(0.0, 1.0)),
    shadows: glow <= 0.02
        ? null
        : [
            Shadow(
              color: glowColor.withValues(alpha: 0.85 * glow),
              blurRadius: 14,
            ),
          ],
  );
}
