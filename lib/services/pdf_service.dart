import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/detection_models.dart';

class PdfService {
  /// Generates a branded PoulTech Fertility Report PDF.
  /// Returns raw PDF bytes ready to save or share.
  static Future<Uint8List> generate({
    required File imageFile,
    required String reportText,
    required Map<String, dynamic> stats,
    required List<EggDetectionResult> results,
  }) async {
    final pdf = pw.Document();

    // Load egg image
    final imageBytes = await imageFile.readAsBytes();
    final pdfImage = pw.MemoryImage(imageBytes);
    final decodedImage = img.decodeImage(imageBytes);
    final double origW = decodedImage?.width.toDouble() ?? 1000.0;
    final double origH = decodedImage?.height.toDouble() ?? 1000.0;

    // Calculate aspect-ratio retaining dimensions for side-by-side images
    final maxAvailableWidth = 480.0; // Total width for the row
    final individualWidth = (maxAvailableWidth - 10) / 2; // 10 is spacing
    final displayHeight = (origH / origW) * individualWidth;
    final scale = individualWidth / origW;

    final total = stats['total'] ?? 0;
    final fertile = stats['fertile'] ?? 0;
    final infertile = stats['infertile'] ?? 0;
    final rate = total > 0
        ? (fertile / total * 100).toStringAsFixed(1)
        : '0.0';
    final timestamp = DateTime.now();
    final dateStr =
        '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';

    // Brand colors
    const brandBlue = PdfColor.fromInt(0xFF2563EB);
    const brandGreen = PdfColor.fromInt(0xFF10B981);
    const brandRed = PdfColor.fromInt(0xFFEF4444);
    const darkBg = PdfColor.fromInt(0xFF0F172A);
    const lightText = PdfColor.fromInt(0xFFE2E8F0);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // ── Header ──────────────────────────────────────────────────────────
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: pw.BoxDecoration(
              color: darkBg,
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'PoulTech',
                      style: pw.TextStyle(
                        color: brandBlue,
                        fontSize: 26,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Fertility Report',
                      style: pw.TextStyle(
                        color: lightText,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Generated: $dateStr  |  AI-Powered Egg Analysis',
                  style: pw.TextStyle(color: PdfColors.grey400, fontSize: 10),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 20),

          // ── Before & After Images ────────────────────────────────────────────
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              // Original Image
              pw.Column(
                 children: [
                    pw.Text('Original Input', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                    pw.SizedBox(height: 5),
                    pw.ClipRRect(
                      horizontalRadius: 8,
                      verticalRadius: 8,
                      child: pw.SizedBox(
                        width: individualWidth,
                        height: displayHeight,
                        child: pw.Image(pdfImage, fit: pw.BoxFit.fill),
                      ),
                    ),
                 ]
              ),

              // AI Detection Overlay
              pw.Column(
                 children: [
                    pw.Text('AI Detection Output', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                    pw.SizedBox(height: 5),
                    pw.ClipRRect(
                      horizontalRadius: 8,
                      verticalRadius: 8,
                      child: pw.SizedBox(
                        width: individualWidth,
                        height: displayHeight,
                        child: pw.Stack(
                          children: [
                            pw.Image(pdfImage, fit: pw.BoxFit.fill),
                            ...results.map((r) {
                              return pw.Positioned(
                                left: r.box.x * scale,
                                top: r.box.y * scale,
                                child: pw.Container(
                                  width: r.box.width * scale,
                                  height: r.box.height * scale,
                                  decoration: pw.BoxDecoration(
                                    border: pw.Border.all(
                                      color: r.isFertile ? brandGreen : brandRed,
                                      width: 1.0,
                                    ),
                                    borderRadius: pw.BorderRadius.circular(2),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                 ]
              ),
            ],
          ),

          pw.SizedBox(height: 20),

          // ── Stats Cards ──────────────────────────────────────────────────────
          pw.Text(
            'Detection Summary',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              _statCard('Total Eggs', '$total', brandBlue),
              pw.SizedBox(width: 10),
              _statCard('Fertile', '$fertile', brandGreen),
              pw.SizedBox(width: 10),
              _statCard('Infertile', '$infertile', brandRed),
              pw.SizedBox(width: 10),
              _statCard('Fertility Rate', '$rate%', brandBlue),
            ],
          ),

          pw.SizedBox(height: 20),

          // ── Stats Table ──────────────────────────────────────────────────────
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(1),
            },
            children: [
              _tableRow('Metric', 'Value', isHeader: true),
              _tableRow('Total Eggs Scanned', '$total'),
              _tableRow('Fertile Eggs', '$fertile'),
              _tableRow('Infertile Eggs', '$infertile'),
              _tableRow('Fertility Rate', '$rate%'),
            ],
          ),

          pw.SizedBox(height: 24),

          // ── AI Report ────────────────────────────────────────────────────────
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                left: pw.BorderSide(color: brandBlue, width: 3),
              ),
            ),
            child: pw.Text(
              'AI Analysis Report',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
            ),
          ),
          pw.SizedBox(height: 10),
          _buildMarkdownText(reportText),

          pw.SizedBox(height: 24),

          // ── Footer ───────────────────────────────────────────────────────────
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 6),
          pw.Text(
            'Generated by PoulTech AI  •  $dateStr  •  Confidential',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static pw.RichText _buildMarkdownText(String text) {
    final spans = <pw.TextSpan>[];
    final parts = text.split('**');
    
    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      
      if (i % 2 == 1) { // It's bold text
        spans.add(pw.TextSpan(
          text: parts[i],
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 11,
            color: PdfColors.black,
            lineSpacing: 2,
          ),
        ));
      } else { // Normal text
        spans.add(pw.TextSpan(
          text: parts[i],
          style: const pw.TextStyle(
            fontSize: 11,
            color: PdfColors.black,
            lineSpacing: 2,
          ),
        ));
      }
    }
    
    return pw.RichText(
      text: pw.TextSpan(children: spans),
      textAlign: pw.TextAlign.justify,
    );
  }

  static pw.Widget _statCard(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: color,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.white),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  static pw.TableRow _tableRow(String col1, String col2,
      {bool isHeader = false}) {
    final style = isHeader
        ? pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)
        : const pw.TextStyle(fontSize: 10);
    final bg = isHeader ? PdfColors.grey200 : PdfColors.white;

    return pw.TableRow(
      decoration: pw.BoxDecoration(color: bg),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: pw.Text(col1, style: style),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: pw.Text(col2, style: style),
        ),
      ],
    );
  }
}
