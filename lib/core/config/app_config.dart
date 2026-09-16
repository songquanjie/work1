/// Compile-time backend address.
///
/// Injected with `--dart-define=API_BASE_URL=...` so a release APK never
/// hard-codes a developer machine. The emulator default is not valid on a
/// physical device.
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );
}
