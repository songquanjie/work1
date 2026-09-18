import 'package:flutter/material.dart';

/// 加载时纯白屏。失败时才给出文案和重试。
class EchoNoteLaunchPage extends StatelessWidget {
  const EchoNoteLaunchPage({
    super.key,
    this.errorMessage,
    this.onRetry,
    this.retrying = false,
  });

  final String? errorMessage;
  final VoidCallback? onRetry;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final String? message = errorMessage;
    return Scaffold(
      key: const Key('launch_blank'),
      backgroundColor: Colors.white,
      body: message == null
          ? const SizedBox.expand()
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF424242),
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (onRetry != null) ...<Widget>[
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: retrying ? null : onRetry,
                      child: Text(retrying ? '正在启动…' : '重试'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
