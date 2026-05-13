import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/detection_models.dart';

/// ONNX inference service.
/// - Input: 1x3x960x960 float32 RGB, 0-1 normalized, letterboxed.
/// - Output: 1x6x18900 raw YOLOv8 (channels-first): channels 0-3 (cx,cy,w,h), 4-5 (class scores).
class ONNXService {
  static const _channel = MethodChannel('poultech/onnx');

  static const int _inputSize = 960;
  static const int _numAnchors = 18900; // 120^2 + 60^2 + 30^2 at 960px
  static const int _numClasses = 2;

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

    const int expectedSize = 1 * (4 + _numClasses) * _numAnchors;
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
    // Raw YOLOv8 output: [1, 4+numClasses, numAnchors], channels-first.
    // Flat index for channel c, anchor n: c * numAnchors + n.
    final List<_DetectionCandidate> candidates = [];

    for (int n = 0; n < _numAnchors; n++) {
      // Find best class
      double bestScore = 0;
      int bestClass = 0;
      for (int c = 0; c < _numClasses; c++) {
        final double s = output[(4 + c) * _numAnchors + n];
        if (s > bestScore) {
          bestScore = s;
          bestClass = c;
        }
      }
      if (bestScore < _confThreshold) continue;

      // bbox in letterbox (960x960) pixel coordinates, cx/cy/w/h
      final double cx = output[0 * _numAnchors + n];
      final double cy = output[1 * _numAnchors + n];
      final double w = output[2 * _numAnchors + n];
      final double h = output[3 * _numAnchors + n];

      double x1 = cx - w / 2;
      double y1 = cy - h / 2;
      double x2 = cx + w / 2;
      double y2 = cy + h / 2;

      // Reverse letterbox: subtract padding, divide by ratio -> original image coords
      x1 = (x1 - padW) / ratio;
      y1 = (y1 - padH) / ratio;
      x2 = (x2 - padW) / ratio;
      y2 = (y2 - padH) / ratio;

      x1 = x1.clamp(0, imgWidth.toDouble());
      y1 = y1.clamp(0, imgHeight.toDouble());
      x2 = x2.clamp(0, imgWidth.toDouble());
      y2 = y2.clamp(0, imgHeight.toDouble());

      final double bw = x2 - x1;
      final double bh = y2 - y1;
      if (bw <= 1 || bh <= 1) continue;

      candidates.add(_DetectionCandidate(
        score: bestScore,
        classId: bestClass,
        box: BoundingBox(x1, y1, bw, bh),
      ));
    }

    // Sort by score desc, then NMS
    candidates.sort((a, b) => b.score.compareTo(a.score));

    final List<EggDetectionResult> kept = [];
    final List<bool> suppressed = List<bool>.filled(candidates.length, false);

    for (int i = 0; i < candidates.length; i++) {
      if (suppressed[i]) continue;
      final ci = candidates[i];
      kept.add(EggDetectionResult(ci.box, ci.classId == 0, ci.score));
      if (kept.length >= _maxDetections) break;
      for (int j = i + 1; j < candidates.length; j++) {
        if (suppressed[j]) continue;
        if (_calculateIOU(ci.box, candidates[j].box) > _iouThreshold) {
          suppressed[j] = true;
        }
      }
    }

    return kept;
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

