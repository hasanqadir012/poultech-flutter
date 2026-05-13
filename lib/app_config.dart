/// Central place to tune data-fetch limits and environment config.
/// Change a value here and it applies everywhere it is referenced.
abstract final class AppConfig {
  /// Backend base URL — swap to Railway URL before production deployment.
  // static const String backendBaseUrl = 'https://poultech-backend-production.up.railway.app';
  static const String backendBaseUrl = 'http://192.168.0.44:3000';
  /// Reports sent to the Knowledge Assistant (Gemini chat) as context.
  static const int chatContextReports = 20;
}
