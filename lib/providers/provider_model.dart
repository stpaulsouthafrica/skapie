import 'package:skapie/providers/model_surface.dart';

class ProviderModel {
  const ProviderModel({
    required this.id,
    required this.surface,
    this.displayName,
    this.show = true,
    this.vanillaOk = true,
  });

  final String id;
  final ModelSurface surface;
  final String? displayName;
  final bool show;
  final bool vanillaOk;
}
