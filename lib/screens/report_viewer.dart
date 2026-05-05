import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/report_model.dart';

class ReportViewerScreen extends StatelessWidget {
  final ReportModel report;
  const ReportViewerScreen({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          report.batchLabel ?? 'Report ${report.formattedDate}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          children: [
            // Stats row
            Row(
              children: [
                _statChip('Total', '${report.totalEggs}', const Color(0xFF3B82F6)),
                const SizedBox(width: 8),
                _statChip('Fertile', '${report.fertileEggs}', const Color(0xFF10B981)),
                const SizedBox(width: 8),
                _statChip('Infertile', '${report.infertileEggs}', const Color(0xFFEF4444)),
                const SizedBox(width: 8),
                _statChip('Rate', report.fertilityPercent, _statusColor),
              ],
            ),
            const SizedBox(height: 8),
            // Date + batch label
            Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 14, color: Colors.white.withOpacity(0.4)),
                const SizedBox(width: 6),
                Text(
                  report.formattedDate,
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Report body — markdown rendered
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Markdown(
                  data: report.reportText,
                  padding: const EdgeInsets.all(16),
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(color: Colors.white, fontSize: 15, height: 1.6),
                    h1: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      height: 2.0,
                    ),
                    h2: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      height: 1.8,
                    ),
                    h3: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.6,
                    ),
                    strong: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    em: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontStyle: FontStyle.italic,
                      fontSize: 15,
                    ),
                    listBullet: const TextStyle(color: Color(0xFF3B82F6), fontSize: 15),
                    blockquote: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                    blockquoteDecoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: const Color(0xFF3B82F6), width: 3),
                      ),
                      color: Colors.white.withOpacity(0.04),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color get _statusColor {
    switch (report.status) {
      case FertilityStatus.good:
        return const Color(0xFF10B981);
      case FertilityStatus.moderate:
        return const Color(0xFFF59E0B);
      case FertilityStatus.poor:
        return const Color(0xFFEF4444);
    }
  }

  Widget _statChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
