import 'package:flutter/foundation.dart';

/// Bounding box describing the detected egg location in the image.
@immutable
class BoundingBox {
  final double x;
  final double y;
  final double width;
  final double height;

  const BoundingBox(this.x, this.y, this.width, this.height);
}

/// Structured detection result including the bounding box and fertility flag.
@immutable
class EggDetectionResult {
  final BoundingBox box;
  final bool isFertile;
  final double confidence; // Confidence score (0.0 to 1.0)

  const EggDetectionResult(this.box, this.isFertile, [this.confidence = 1.0]);
}

