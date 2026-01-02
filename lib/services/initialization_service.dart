import 'dart:io';

import 'onnx_service.dart';

/// Handles app start-up tasks such as model warm-up and connectivity checks.
class InitializationService {
  /// Preload or warm up ONNX models. Currently a no-op with a simulated delay.
  static Future<void> preloadModels() async {
    await ONNXService.ensureModelLoaded();
  }

  /// Basic connectivity check. Returns true if a simple DNS lookup succeeds.
  static Future<bool> checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('example.com');
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

