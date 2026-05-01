import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/detection_models.dart';

/// ONNX inference service.
/// - Input: 1x3x640x640 float32 RGB, 0-1 normalized, letterboxed.
/// - Output: 1x300x6 (YOLOv8 Post-NMS), indices: 0-3 (x1,y1,x2,y2), 4 (score), 5 (class_id).
class ONNXService {
  static const _channel = MethodChannel('poultech/onnx');

  // YOLOv8 Post-processing thresholds
  static const double _confThreshold = 0.30;
  static const double _iouThreshold = 0.45;
  static const int _maxDetections = 100;

  static List<EggDetectionResult>? _lastDetections;

  /// Ensure model bytes are loaded.
  static Future<void> ensureModelLoaded() async {
    // Model is loaded natively in MainActivity.kt
    // Removed Dart-side loading to prevent Out of Memory (OOM) crashes on Android
    return;
  }

  /// Run detection and return bounding boxes.
  static Future<List<BoundingBox>> runDetection(File imageFile) async {
    final detections = await _runFullInference(imageFile);
    _lastDetections = detections;
    return detections.map((e) => e.box).toList(growable: false);
  }

  /// Return detection results with fertility flag.
  static Future<List<EggDetectionResult>> runClassification(
    File imageFile,
    List<BoundingBox> boxes,
  ) async {
    if (_lastDetections != null && _lastDetections!.length == boxes.length) {
      return _lastDetections!;
    }
    final detections = await _runFullInference(imageFile);
    _lastDetections = detections;
    return detections;
  }

  /// Generates a summary map of the detections for the LLM Report service.
  /// Call this with the results from runClassification.
  static Map<String, dynamic> getSummaryStats(
    List<EggDetectionResult> results,
  ) {
    int fertile = 0;
    int infertile = 0;

    for (var res in results) {
      if (res.isFertile) {
        fertile++;
      } else {
        infertile++;
      }
    }

    return {
      'total': fertile + infertile,
      'fertile': fertile,
      'infertile': infertile,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  static Future<List<EggDetectionResult>> _runFullInference(
    File imageFile,
  ) async {
    await ensureModelLoaded();

    final Float32List output;
    int imgWidth;
    int imgHeight;
    double ratio;
    double padW;
    double padH;

    try {
      final result = await _channel.invokeMethod('runModel', {
        'imagePath': imageFile.absolute.path,
      });

      if (result == null) {
        throw Exception('ONNX runtime returned null');
      }

      final Map<dynamic, dynamic> resultMap = result as Map<dynamic, dynamic>;
      
      final rawOutput = resultMap['output'];
      if (rawOutput is Float32List) {
        output = rawOutput;
      } else {
        output = Float32List.fromList((rawOutput as List<dynamic>).cast<double>());
      }
      
      imgWidth = (resultMap['imgWidth'] as num).toInt();
      imgHeight = (resultMap['imgHeight'] as num).toInt();
      ratio = (resultMap['ratio'] as num).toDouble();
      padW = (resultMap['padW'] as num).toDouble();
      padH = (resultMap['padH'] as num).toDouble();
      
    } on MissingPluginException {
      throw Exception('MethodChannel "poultech/onnx" not implemented.');
    }

    const int expectedSize = 1 * 300 * 6;
    if (output.length != expectedSize) {
      debugPrint('Warning: Unexpected output length: ${output.length}. Expected $expectedSize');
    }

    return _postprocess(
      output: output,
      imgWidth: imgWidth,
      imgHeight: imgHeight,
      ratio: ratio,
      padW: padW,
      padH: padH,
    );
  }

  // --- Postprocess ---

  static List<EggDetectionResult> _postprocess({
    required Float32List output,
    required int imgWidth,
    required int imgHeight,
    required double ratio,
    required double padW,
    required double padH,
  }) {
    const int maxDetections = 300;
    final List<EggDetectionResult> results = [];

    // YOLOv8 Post-NMS Output is [1, 300, 6]
    // Each detection: [x1, y1, x2, y2, score, class_id]
    for (int i = 0; i < maxDetections; i++) {
      final int baseIdx = i * 6;

      // Skip padding (detections with all zeros)
      final double x1Raw = output[baseIdx + 0];
      final double y1Raw = output[baseIdx + 1];
      final double x2Raw = output[baseIdx + 2];
      final double y2Raw = output[baseIdx + 3];
      final double score = output[baseIdx + 4];
      final double classIdFloat = output[baseIdx + 5];

      // Skip empty detections (padding)
      if (x1Raw == 0 && y1Raw == 0 && x2Raw == 0 && y2Raw == 0 && score == 0) {
        continue;
      }

      // Apply confidence threshold
      if (score < _confThreshold) continue;

      final int classId = classIdFloat.round();

      // Remove padding/scaling from letterbox coordinates
      double x1 = (x1Raw - padW) / ratio;
      double y1 = (y1Raw - padH) / ratio;
      double x2 = (x2Raw - padW) / ratio;
      double y2 = (y2Raw - padH) / ratio;

      // Convert to x, y, width, height format and clamp to image bounds
      final double width = (x2 - x1).clamp(0, imgWidth.toDouble());
      final double height = (y2 - y1).clamp(0, imgHeight.toDouble());

      results.add(
        EggDetectionResult(
          BoundingBox(
            x1.clamp(0, imgWidth.toDouble()),
            y1.clamp(0, imgHeight.toDouble()),
            width,
            height,
          ),
          classId == 0, // fertile if class 0
          score,
        ),
      );

      // Limit to max detections
      if (results.length >= _maxDetections) break;
    }

    return results;
  }

  static double _calculateIOU(BoundingBox a, BoundingBox b) {
    final double areaA = a.width * a.height;
    final double areaB = b.width * b.height;

    final double interX1 = math.max(a.x, b.x);
    final double interY1 = math.max(a.y, b.y);
    final double interX2 = math.min(a.x + a.width, b.x + b.width);
    final double interY2 = math.min(a.y + a.height, b.y + b.height);

    final double interWidth = math.max(0, interX2 - interX1);
    final double interHeight = math.max(0, interY2 - interY1);
    final double interArea = interWidth * interHeight;

    if (interArea <= 0) return 0;
    return interArea / (areaA + areaB - interArea);
  }
}

class _DetectionCandidate {
  final double score;
  final int classId;
  final BoundingBox box;
  _DetectionCandidate({
    required this.score,
    required this.classId,
    required this.box,
  });
}

