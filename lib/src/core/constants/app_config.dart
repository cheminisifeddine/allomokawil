/// App-level configuration.
///
/// The API host is injected at build time via --dart-define so no secret is
/// ever committed:
///   flutter build apk --dart-define=API_BASE_URL=https://allomokawil.colisify.com
///
/// The app carries TWO hosts (primary + fallback) and fails over between them,
/// so a DNS/zone problem on one host never bricks the app on Algerian networks.
class AppConfig {
  AppConfig._();

  /// Primary API host (Cloudflare custom domain).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://allomokawil.colisify.com',
  );

  /// Secondary API host used only when the primary is unreachable.
  static const String apiFallbackUrl = String.fromEnvironment(
    'API_FALLBACK_URL',
    defaultValue: 'https://finili.medsaidkichene.workers.dev',
  );

  /// Primary first, then fallback; blanks dropped, trailing slashes trimmed.
  static List<String> get apiBaseUrls => <String>[
        apiBaseUrl,
        apiFallbackUrl,
      ]
          .map((u) => u.trim().replaceAll(RegExp(r'/+$'), ''))
          .where((u) => u.isNotEmpty)
          .toList();

  static const String appName = 'الو موكاول';
  static const String appNameLatin = 'Allo Mokawil';
}
