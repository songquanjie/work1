import 'package:flutter/material.dart';

import 'app_bootstrap.dart';

/// 立刻画出白屏，数据库在后台打开，避免启动卡住无响应。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EchoNoteBootstrap());
}
