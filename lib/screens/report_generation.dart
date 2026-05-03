import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';

import '../models/detection_models.dart';
import '../models/report_model.dart';
import '../services/database_service.dart';
import '../services/llm_service.dart';
import '../services/onnx_service.dart';
import '../services/pdf_service.dart';

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
  bool _isPdfLoading = false;
  bool _isSaving = false;
  bool _isSaved = false;
  Map<String, dynamic> _structuredStats = {};
  final DatabaseService _databaseService = DatabaseService();

  @override
  void initState() {
    super.initState();
    _generateReport();
  }

  /// 🧹 Cleans markdown-like formatting coming from LLM
  String _sanitizeLLMOutput(String text) {
    return text
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
        _structuredStats = structuredData;
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
                          child: MarkdownBody(
                            data: _reportText,
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                height: 1.4,
                              ),
                              strong: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              listBullet: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            if (_isPdfLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text('Generating PDF...', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            Row(
              children: [
                // ── Save to account (MongoDB) ──────────────────────────────
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_isLoading || _isSaving || _isSaved)
                        ? null
                        : () async {
                            setState(() => _isSaving = true);

                            final uid = FirebaseAuth.instance.currentUser?.uid;
                            if (uid == null) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please sign in to save reports.'),
                                    backgroundColor: Color(0xFFEF4444),
                                  ),
                                );
                                setState(() => _isSaving = false);
                              }
                              return;
                            }

                            final total = (_structuredStats['total'] as int?) ?? widget.results.length;
                            final fertile = (_structuredStats['fertile'] as int?) ?? widget.results.where((r) => r.isFertile).length;
                            final infertile = total - fertile;
                            final rate = total > 0 ? fertile / total : 0.0;

                            debugPrint('[REPORT] Saving report — uid: $uid, '
                                'total: $total, fertile: $fertile, rate: $rate');

                            final report = ReportModel(
                              userId: uid,
                              createdAt: DateTime.now(),
                              totalEggs: total,
                              fertileEggs: fertile,
                              infertileEggs: infertile,
                              fertilityRate: rate,
                              reportText: _reportText,
                              imagePath: widget.imageFile.path,
                            );

                            final result = await _databaseService.saveReport(report);

                            if (mounted) {
                              setState(() {
                                _isSaving = false;
                                _isSaved = result.isSuccess;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    result.isSuccess
                                        ? '✓ Report saved to your account'
                                        : result.errorMessage ?? 'Save failed. Please try again.',
                                  ),
                                  backgroundColor: result.isSuccess
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFEF4444),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              );
                            }
                          },
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(_isSaved ? Icons.check_circle_outline : Icons.cloud_upload_outlined),
                    label: Text(_isSaved ? 'Saved ✓' : 'Save'),
                    style: _primaryButtonStyle(
                      _isSaved ? const Color(0xFF10B981) : const Color(0xFF2563EB),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // ── Share via share sheet (WhatsApp, Gmail, etc.) ──────────
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_isLoading || _isPdfLoading)
                        ? null
                        : () async {
                            setState(() => _isPdfLoading = true);
                            try {
                              final bytes = await PdfService.generate(
                                imageFile: widget.imageFile,
                                reportText: _reportText,
                                stats: _structuredStats,
                                results: widget.results,
                              );
                              await Printing.sharePdf(
                                bytes: bytes,
                                filename: 'poultech_fertility_report.pdf',
                              );
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error sharing: $e')),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _isPdfLoading = false);
                            }
                          },
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share'),
                    style: _primaryButtonStyle(const Color(0xFF10B981)),
                  ),
                ),
                const SizedBox(width: 10),
                // ── Open in PDF viewer ─────────────────────────────────────
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_isLoading || _isPdfLoading)
                        ? null
                        : () async {
                            setState(() => _isPdfLoading = true);
                            try {
                              final bytes = await PdfService.generate(
                                imageFile: widget.imageFile,
                                reportText: _reportText,
                                stats: _structuredStats,
                                results: widget.results,
                              );
                              await Printing.layoutPdf(
                                onLayout: (_) async => bytes,
                                name: 'poultech_fertility_report',
                              );
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _isPdfLoading = false);
                            }
                          },
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print PDF'),
                    style: _primaryButtonStyle(const Color(0xFFF59E0B)),
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
