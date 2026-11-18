import 'package:flutter/material.dart';

import 'ui/piano_roll/editor_app.dart';

/// Flutter 应用从 main 开始运行。
void main() {
  // 把根组件交给 Flutter，之后 Flutter 会负责显示和更新界面。
  runApp(const ChangvoxApp());
}

/// 整个应用的外层组件：设置应用标题、配色和首页。
class ChangvoxApp extends StatelessWidget {
  const ChangvoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CHANGVOX 原型',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff6750a4)),
        useMaterial3: true,
      ),
      home: const EditorApp(),
    );
  }
}
