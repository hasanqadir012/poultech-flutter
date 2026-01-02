import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/detection_models.dart';

/// Service for single-egg fertility detection using Roboflow API
class RoboflowService {
  static const String _apiUrl = 'https://serverless.roboflow.com';
  static const String _apiKey = 'FuOncPvT41FZDfg0w9U8';
  static const String _modelId = 'egg-fertility-detection/1';

  /// Run single-egg detection on the provided image file
  static Future<List<EggDetectionResult>> runSingleEggDetection(File imageFile) async {
    try {
      // Prepare multipart request
      final uri = Uri.parse('$_apiUrl/$_modelId?api_key=$_apiKey');
      final request = http.MultipartRequest('POST', uri);
      
      // Add image file
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        imageFile.path,
      ));

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        throw Exception('Roboflow API error: ${response.statusCode} - ${response.body}');
      }

      // Parse response
      final jsonResponse = json.decode(response.body);
      
      // Parse predictions
      final predictions = jsonResponse['predictions'] as List<dynamic>;
      final results = <EggDetectionResult>[];

      for (final pred in predictions) {
        final x = (pred['x'] as num).toDouble();
        final y = (pred['y'] as num).toDouble();
        final width = (pred['width'] as num).toDouble();
        final height = (pred['height'] as num).toDouble();
        final confidence = (pred['confidence'] as num).toDouble();
        final className = pred['class'] as String;

        // Convert center coordinates to top-left coordinates
        final boxX = x - width / 2;
        final boxY = y - height / 2;

        // Determine if fertile based on class name
        final isFertile = className.toLowerCase() == 'fertile';

        results.add(EggDetectionResult(
          BoundingBox(boxX, boxY, width, height),
          isFertile,
          confidence,
        ));
      }

      return results;
    } catch (e) {
      throw Exception('Failed to run Roboflow detection: $e');
    }
  }
}
