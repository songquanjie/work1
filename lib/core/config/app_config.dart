/// 编译期注入的后端地址。
///
/// 用 `--dart-define=API_BASE_URL=...` 打进 APK，避免写死开发机 IP。
/// 默认 `10.0.2.2` 只给模拟器访问电脑，真机必须改成局域网或公网地址。
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );
}
