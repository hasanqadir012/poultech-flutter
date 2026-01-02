import 'dart:io';

import 'package:flutter/material.dart';

import '../models/detection_models.dart';
import '../services/llm_service.dart';
import '../services/onnx_service.dart';

class ReportGenerationScreen extends StatefulWidget {
  final File imageFile;
  final List<EggDetectionResult> results;

  const ReportGenerationScreen({
    super.key,
    required this.imageFile,
    required this.results,
  });

  @override
  State<ReportGenerationScreen> createState() =>
      _ReportGenerationScreenState();
}

class _ReportGenerationScreenState extends State<ReportGenerationScreen> {
  String _reportText = "Generating professional report...";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _generateReport();
  }

  /// 🧹 Cleans markdown-like formatting coming from LLM
  String _sanitizeLLMOutput(String text) {
    return text
        // Remove **bold**
        .replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'$1')
        // Remove single *
        .replaceAll('*', '')
        // Remove markdown headings ###
        .replaceAll(RegExp(r'#+\s?'), '')
        // Normalize extra newlines
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  Future<void> _generateReport() async {
    try {
      if (widget.results.isEmpty) {
        setState(() {
          _reportText =
              "No eggs detected. Please run detection again with a clearer image.";
          _isLoading = false;
        });
        return;
      }

      // Get structured stats for LLM
      final structuredData =
          ONNXService.getSummaryStats(widget.results);

      // Generate report from LLM
      final rawReport = await LLMService.generateReport(
        widget.imageFile,
        structuredData,
      );

      // ✅ Sanitize markdown output
      final cleanedReport = _sanitizeLLMOutput(rawReport);

      setState(() {
        _reportText = cleanedReport;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _reportText = "Error generating report: $e";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Fertility Report'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E293B), Color(0xFF111827)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: const [
                  Icon(Icons.description_outlined,
                      color: Colors.white70),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your professional report will be ready in a moment.',
                      style: TextStyle(
                          color: Colors.white, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF22D3EE)),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: SingleChildScrollView(
                          child: Text(
                            _reportText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(
                              const SnackBar(
                                  content: Text('Report Saved.')),
                            );
                          },
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Save'),
                    style: _primaryButtonStyle(
                        const Color(0xFF2563EB)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(
                              const SnackBar(
                                  content: Text('Sharing Report...')),
                            );
                          },
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share'),
                    style: _primaryButtonStyle(
                        const Color(0xFF10B981)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Exporting to PDF...')),
                            );
                          },
                    icon: const Icon(
                        Icons.picture_as_pdf_outlined),
                    label: const Text('Export PDF'),
                    style: _primaryButtonStyle(
                        const Color(0xFFF59E0B)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _primaryButtonStyle(Color color) {
    return ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
