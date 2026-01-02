import 'package:flutter/material.dart';
import 'report_history.dart';

class ReportViewerScreen extends StatelessWidget {
  final SavedReport report;
  const ReportViewerScreen({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Report #${report.id}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Summary', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(report.summary, style: const TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    report.fullContent,
                    style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(context, Icons.share_outlined, 'Share', 'Sharing Report...'),
                _buildActionButton(context, Icons.picture_as_pdf_outlined, 'Export', 'Exporting to PDF...'),
                _buildActionButton(context, Icons.delete_outline, 'Delete', 'Deleting Report...'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, IconData icon, String label, String toast) {
    return Column(
      children: [
        IconButton(
          icon: Icon(icon, color: Colors.white),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toast)));
            if (label == 'Delete') Navigator.of(context).pop();
          },
        ),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
