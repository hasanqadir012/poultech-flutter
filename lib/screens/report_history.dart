import 'package:flutter/material.dart';
import '../models/report_model.dart';
import '../services/database_service.dart';
import 'report_viewer.dart';

class ReportHistoryScreen extends StatefulWidget {
  const ReportHistoryScreen({super.key});

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  final DatabaseService _db = DatabaseService();
  List<ReportModel> _reports = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  Future<void> _fetchReports() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final reports = await _db.getReports();
    if (mounted) {
      setState(() {
        _reports = reports;
        _isLoading = false;
        if (reports.isEmpty) _errorMessage = null;
      });
    }
  }

  Future<void> _confirmDelete(ReportModel report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Report?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will permanently delete the report for ${report.totalEggs} eggs '
          '(${report.fertilityPercent} fertility) from ${report.formattedDate}.',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final success = await _db.deleteReport(report.id!);
    if (mounted) {
      if (success) {
        setState(() => _reports.removeWhere((r) => r.id == report.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Report deleted.'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to delete. Check your connection.'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Report History',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_outlined, size: 56, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 15),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _fetchReports,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Try Again', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (_reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_outlined, size: 64, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              'No reports yet',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Run a detection and save your first report.',
              style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchReports,
      color: const Color(0xFF3B82F6),
      backgroundColor: const Color(0xFF1E293B),
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _reports.length,
        itemBuilder: (context, index) {
          return _ReportCard(
            report: _reports[index],
            onDelete: () => _confirmDelete(_reports[index]),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReportViewerScreen(report: _reports[index]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final ReportModel report;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _ReportCard({required this.report, required this.onDelete, required this.onTap});

  String _plainPreview(String text) {
    return text
        .replaceAll(RegExp(r'\*\*|##\s?|#\s?|\*'), '')
        .replaceAll(RegExp(r'\n{2,}'), ' ')
        .trim();
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Fertility rate circle
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: _statusColor.withOpacity(0.4)),
                ),
                child: Center(
                  child: Text(
                    report.fertilityPercent,
                    style: TextStyle(
                      color: _statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.batchLabel ?? '${report.totalEggs} eggs analysed',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${report.fertileEggs} fertile · ${report.infertileEggs} infertile',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      report.formattedDate,
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Delete button
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.15)),
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    color: Color(0xFFEF4444),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          if (report.reportText.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 12),
            Text(
              () {
                final plain = _plainPreview(report.reportText);
                return plain.length > 140 ? '${plain.substring(0, 140)}…' : plain;
              }(),
              style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Tap to view full report →',
                style: TextStyle(
                  color: const Color(0xFF3B82F6).withOpacity(0.8),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    ));
  }
}
