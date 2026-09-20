import 'package:flutter/material.dart';
import 'package:skapie/app/home_screen.dart';
import 'package:skapie/app/theme.dart';
import 'package:skapie/scene/scene_store.dart';
import 'package:skapie/shared/app_info.dart';

class SkapieApp extends StatelessWidget {
  const SkapieApp({super.key, required this.store});

  final SceneStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.windowTitle,
      theme: buildAppTheme(),
      home: HomeScreen(store: store),
    );
  }
}
