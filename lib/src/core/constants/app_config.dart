/// App-level configuration.
///
/// The API base URL is injected at build time via --dart-define
/// so no secret is ever committed:
///   flutter run --dart-define=API_BASE_URL=https://api.allomokawil.dz
/// When unset, it defaults to the local dev server.
class AppConfig {
  AppConfig._();

  /// Base URL of the Allo Mokawil API (CF Workers).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8787',
  );

  static const String appName = 'الو موكاول';
  static const String appNameLatin = 'Allo Mokawil';
}