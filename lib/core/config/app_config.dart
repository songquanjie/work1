/// 编译期注入的后端地址。
///
/// 默认指向已部署的云服务器，别人 clone 后直接打包即可访问公网后端。
/// 本地改打局域网时仍可用 `--dart-define=API_BASE_URL=...` 覆盖。
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://39.96.17.209:3000',
  );
}
