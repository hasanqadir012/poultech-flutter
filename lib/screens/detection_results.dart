import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/detection_models.dart';
import 'report_generation.dart';

class DetectionResultsScreen extends StatelessWidget {
  final File imageFile;
  final List<EggDetectionResult> results;

  const DetectionResultsScreen({super.key, required this.imageFile, required this.results});

  int get _totalEggs => results.length;
  int get _fertileEggs => results.where((e) => e.isFertile).length;
  int get _infertileEggs => results.where((e) => !e.isFertile).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Detection Results'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: FutureBuilder<Uint8List>(
                future: imageFile.readAsBytes(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  
                  final originalImage = img.decodeImage(snapshot.data!);
                  final origWidth = originalImage?.width ?? 1;
                  final origHeight = originalImage?.height ?? 1;
                  
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final containerWidth = constraints.maxWidth;
                      final containerHeight = constraints.maxHeight;
                      
                      // Calculate scale factor for BoxFit.cover
                      final scaleX = containerWidth / origWidth;
                      final scaleY = containerHeight / origHeight;
                      final scale = scaleX > scaleY ? scaleX : scaleY; // BoxFit.cover uses the larger scale
                      
                      // Calculate offset for centering (BoxFit.cover centers the image)
                      final scaledWidth = origWidth * scale;
                      final scaledHeight = origHeight * scale;
                      final offsetX = (containerWidth - scaledWidth) / 2;
                      final offsetY = (containerHeight - scaledHeight) / 2;
                      
                      return Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white12),
                          image: DecorationImage(image: FileImage(imageFile), fit: BoxFit.cover),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              right: 12,
                              top: 12,
                              child: _pill('${_fertileEggs} fertile', Colors.greenAccent),
                            ),
                            Positioned(
                              right: 12,
                              top: 48,
                              child: _pill('${_infertileEggs} infertile', Colors.redAccent),
                            ),
                            ...results.map((result) {
                              // Scale coordinates from original image space to displayed space
                              final left = offsetX + result.box.x * scale;
                              final top = offsetY + result.box.y * scale;
                              final w = result.box.width * scale;
                              final h = result.box.height * scale;
                          
                              return Stack(
                                children: [
                                  // Bounding box
                                   Positioned(
                                     left: left,
                                     top: top,
                                     child: Container(
                                       width: w,
                                       height: h,
                                       decoration: BoxDecoration(
                                         border: Border.all(
                                           color: result.isFertile ? Colors.greenAccent : Colors.redAccent,
                                           width: 2,
                                         ),
                                         borderRadius: BorderRadius.circular(4),
                                       ),
                                     ),
                                   ),
                                  // Label with ID and confidence
                                   if (top > 20) // Only show label if there's space above
                                     Positioned(
                                       left: left,
                                       top: top - 20,
                                       child: Container(
                                         padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                         decoration: BoxDecoration(
                                           color: (result.isFertile ? Colors.greenAccent : Colors.redAccent).withOpacity(0.9),
                                           borderRadius: BorderRadius.circular(4),
                                         ),
                                         child: Text(
                                           '${result.isFertile ? "Fertile" : "Infertile"} ${result.confidence.toStringAsFixed(2)}',
                                           style: const TextStyle(
                                             color: Colors.black87,
                                             fontSize: 11,
                                             fontWeight: FontWeight.w600,
                                           ),
                                         ),
                                       ),
                                     )
                                   else // Show label below if no space above
                                     Positioned(
                                       left: left,
                                       top: top + h + 2,
                                       child: Container(
                                         padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                         decoration: BoxDecoration(
                                           color: (result.isFertile ? Colors.greenAccent : Colors.redAccent).withOpacity(0.9),
                                           borderRadius: BorderRadius.circular(4),
                                         ),
                                         child: Text(
                                           '${result.isFertile ? "Fertile" : "Infertile"} ${result.confidence.toStringAsFixed(2)}',
                                           style: const TextStyle(
                                             color: Colors.black87,
                                             fontSize: 11,
                                             fontWeight: FontWeight.w600,
                                           ),
                                         ),
                                       ),
                                     ),
                                ],
                              );
                            }),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 14, offset: const Offset(0, 6)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.analytics_outlined, color: Colors.white70),
                        SizedBox(width: 8),
                        Text('Summary', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _statCard('Total', _totalEggs.toString(), Colors.blueAccent),
                        _statCard('Fertile', _fertileEggs.toString(), Colors.greenAccent),
                        _statCard('Infertile', _infertileEggs.toString(), Colors.redAccent),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ReportGenerationScreen(
                                results: results,
                                imageFile: imageFile,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('Generate Professional Report'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Results saved locally.')),
                        );
                      },
                      icon: const Icon(Icons.save_alt, color: Colors.white70),
                      label: const Text('Save Results', style: TextStyle(color: Colors.white70)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      width: 98,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
