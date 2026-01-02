import 'dart:io';

import 'package:flutter/material.dart';

import '../models/detection_models.dart';
import '../services/onnx_service.dart';
import '../services/roboflow_service.dart';
import 'detection_results.dart';

class DetectionProcessingScreen extends StatefulWidget {
  final File imageFile;
  final String detectionMode; // 'single' or 'multi'
  const DetectionProcessingScreen({super.key, required this.imageFile, required this.detectionMode});

  @override
  State<DetectionProcessingScreen> createState() => _DetectionProcessingScreenState();
}

class _DetectionProcessingScreenState extends State<DetectionProcessingScreen> {
  String _status = "Starting detection...";
  double _progress = 0.0;
  List<EggDetectionResult> _results = [];

  @override
  void initState() {
    super.initState();
    _startProcessing();
  }

  Future<void> _startProcessing() async {
    try {
      if (widget.detectionMode == 'single') {
        // Single-egg detection using Roboflow API
        setState(() {
          _status = "Analyzing egg fertility...";
          _progress = 0.5;
        });
        _results = await RoboflowService.runSingleEggDetection(widget.imageFile);

        setState(() {
          _status = "Processing complete.";
          _progress = 1.0;
        });
      } else {
        // Multi-egg detection using ONNX model
        setState(() {
          _status = "Detecting eggs...";
          _progress = 0.35;
        });
        final boxes = await ONNXService.runDetection(widget.imageFile);

        setState(() {
          _status = "Classifying fertility...";
          _progress = 0.7;
        });
        _results = await ONNXService.runClassification(widget.imageFile, boxes);

        setState(() {
          _status = "Processing complete.";
          _progress = 1.0;
        });
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DetectionResultsScreen(
              imageFile: widget.imageFile,
              results: _results,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _status = "Error: $e";
        _progress = 0.0;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error during processing: $_status")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1224),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.flash_on, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Processing Image',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.1),
                        Colors.white.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 140,
                        height: 140,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 140,
                              height: 140,
                              child: CircularProgressIndicator(
                                value: _progress == 0.0 ? null : _progress,
                                strokeWidth: 8,
                                backgroundColor: Colors.white.withOpacity(0.1),
                                valueColor: const AlwaysStoppedAnimation(Color(0xFF3B82F6)),
                              ),
                            ),
                            const Icon(Icons.egg, size: 42, color: Colors.white70),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(_progress * 100).toInt()}% complete',
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
