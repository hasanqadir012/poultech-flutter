import 'package:flutter/material.dart';

import '../models/agent_analysis_model.dart';
import '../services/agent_analysis_service.dart';

class AgentAnalysisScreen extends StatefulWidget {
  const AgentAnalysisScreen({super.key});

  @override
  State<AgentAnalysisScreen> createState() => _AgentAnalysisScreenState();
}

class _AgentAnalysisScreenState extends State<AgentAnalysisScreen> {
  final AgentAnalysisService _service = AgentAnalysisService();

  bool _isLoading = true;
  bool _isRegenerating = false;
  AgentAnalysisModel? _analysis;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final latest = await _service.getLatest();
    if (mounted) {
      setState(() {
        _analysis = latest;
        _isLoading = false;
      });
    }
  }

  Future<void> _regenerate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Re-run AI Analysis?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'The AI analyst will investigate your latest data and produce a fresh diagnosis. '
          'This takes about 10–15 seconds.',
          style: TextStyle(color: Color(0xFF94A3B8), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Run Analysis', style: TextStyle(color: Color(0xFF3B82F6))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final clickedAt = DateTime.now();
    setState(() => _isRegenerating = true);
    final ok = await _service.forceRegenerate();
    if (!mounted) return;

    if (!ok) {
      setState(() => _isRegenerating = false);
      _snack('Failed to trigger analysis. Check the backend.', isError: true);
      return;
    }

    // Poll up to ~30s for the newly written doc (agent typically takes 10–15s).
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      final latest = await _service.getLatest();
      if (latest != null && latest.generatedAt.isAfter(clickedAt)) {
        setState(() {
          _analysis = latest;
          _isRegenerating = false;
        });
        return;
      }
    }

    if (mounted) {
      setState(() => _isRegenerating = false);
      _snack('Still running in background — pull to refresh in a moment.');
    }
  }

  void _snack(String text, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          'AI Analyst',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Re-run analysis',
            onPressed: _isLoading || _isRegenerating ? null : _regenerate,
            icon: _isRegenerating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF3B82F6),
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final a = _analysis;
    if (a == null) return _buildEmpty();

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF3B82F6),
      backgroundColor: const Color(0xFF1E293B),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          _generatedLabel(a),
          const SizedBox(height: 14),
          _buildDiagnosisCard(a),
          if (a.trendNarrative.trim().isNotEmpty) ...[
            const SizedBox(height: 20),
            _sectionLabel('TREND NARRATIVE'),
            const SizedBox(height: 8),
            _buildTrendNarrativeCard(a.trendNarrative),
          ],
          if (a.evidence.isNotEmpty) ...[
            const SizedBox(height: 20),
            _sectionLabel('EVIDENCE'),
            const SizedBox(height: 8),
            _buildEvidenceCard(a.evidence),
          ],
          if (a.recommendations.isNotEmpty) ...[
            const SizedBox(height: 20),
            _sectionLabel(
              'RECOMMENDATIONS · ${a.recommendations.length}',
            ),
            const SizedBox(height: 8),
            ...a.sortedRecommendations.map(_buildRecCard),
          ],
          if (a.toolsCalled.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildInvestigationTrail(a),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.psychology_outlined,
              color: Colors.white.withValues(alpha: 0.2),
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'No analysis yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Run your first detection. The AI analyst will investigate your data and produce a diagnosis.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _generatedLabel(AgentAnalysisModel a) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'Generated ${_formatDate(a.generatedAt)} · ${a.iterations} reasoning step${a.iterations == 1 ? '' : 's'}',
        style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF64748B),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildDiagnosisCard(AgentAnalysisModel a) {
    final color = a.severity.color;
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(a.severity.icon, color: color, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'DIAGNOSIS · ${a.severity.label.toUpperCase()}',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                a.diagnosis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: Container(
            width: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrendNarrativeCard(String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFCBD5E1),
          fontSize: 13.5,
          height: 1.55,
        ),
      ),
    );
  }

  Widget _buildEvidenceCard(List<String> evidence) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: evidence.map((e) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6, right: 10),
                  child: Icon(Icons.circle, color: Color(0xFF3B82F6), size: 6),
                ),
                Expanded(
                  child: Text(
                    e,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRecCard(AgentRecommendation r) {
    final isUrgent = r.isUrgent;
    final accent = isUrgent ? const Color(0xFFEAB308) : const Color(0xFF3B82F6);
    final label = isUrgent ? 'PRIORITY ${r.priority} · URGENT' : 'PRIORITY ${r.priority}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  r.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
                if (r.body.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    r.body,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvestigationTrail(AgentAnalysisModel a) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.travel_explore, color: Color(0xFF64748B), size: 14),
              const SizedBox(width: 6),
              Text(
                'INVESTIGATION TRAIL · ${a.elapsedMs}ms',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...a.toolsCalled.map((t) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• ${t.name}(${_summarizeArgs(t.args)})',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              )),
        ],
      ),
    );
  }

  String _summarizeArgs(Map<String, dynamic> args) {
    if (args.isEmpty) return '';
    return args.entries.map((e) => '${e.key}: ${e.value}').join(', ');
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}
