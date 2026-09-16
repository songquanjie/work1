import 'package:flutter/material.dart';

import 'features/home/home_page.dart';

class EchoNoteApp extends StatelessWidget {
  const EchoNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '随身录音笔记',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
