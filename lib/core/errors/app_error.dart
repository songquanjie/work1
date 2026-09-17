/// 给用户看的失败。界面只展示 [message]，[code] 留给重试路由和日志。
class AppError implements Exception {
  const AppError({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() => message;
}
