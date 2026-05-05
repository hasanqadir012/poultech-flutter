/// Central place to tune data-fetch limits used across the app.
/// Change a value here and it applies everywhere it is referenced.
abstract final class AppConfig {
  /// Reports sent to the Knowledge Assistant (Gemini chat) as context.
  static const int chatContextReports = 20;
}
