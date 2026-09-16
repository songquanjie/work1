import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';

/// Placeholder home until recording lands in a later change.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('随身录音笔记')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('欢迎使用', style: textTheme.headlineSmall),
            const SizedBox(height: 12),
            const Text('录音、列表和转写将在后续迭代加入。'),
            const SizedBox(height: 24),
            Text('当前服务地址', style: textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(AppConfig.apiBaseUrl, style: textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
