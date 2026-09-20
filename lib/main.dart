import 'package:flutter/material.dart';
import 'package:skapie/app/skapie_app.dart';
import 'package:skapie/scene/scene.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SceneStore(persistence: SceneFilePersistence.projectDefault());
  await store.load();
  runApp(SkapieApp(store: store));
}
