import 'package:flutter/material.dart';

import '../models/recommendation_model.dart';
import '../services/recommendation_service.dart';
import '../services/trend_service.dart';

class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  final RecommendationService _service = RecommendationService();
  final TrendService _trendService = TrendService();

  bool _isLoading = true;
  bool _isRegenerating = false;
  RecommendationsModel? _recommendations;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final rec = await _service.getLatestRecommendations();
      if (mounted) setState(() => _recommendations = rec);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Clear today's docs and regenerate trend + recommendations from scratch.
  /// Polls for the new recommendation since the backend writes it async.
  Future<void> _regenerate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Regenerate Recommendations?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will clear today\'s trend and recommendations, then regenerate them with the latest AI model.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Regenerate', style: TextStyle(color: Color(0xFF3B82F6))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Capture the moment the user clicked regenerate. The new rec must have
    // generatedAt AFTER this — ID comparison alone fails because once today's
    // doc is deleted, /latest returns yesterday's surviving doc (different ID,
    // but it's NOT the freshly regenerated one).
    final regenerateClickedAt = DateTime.now();

    setState(() => _isRegenerating = true);
    final ok = await _trendService.forceRegenerate();
    if (!mounted) return;

    if (!ok) {
      setState(() => _isRegenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to trigger regeneration. Check the backend.'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    // Poll up to ~30s for the truly new doc (Gemini call typically 3-15s)
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      final rec = await _service.getLatestRecommendations();
      if (rec != null && rec.generatedAt.isAfter(regenerateClickedAt)) {
        setState(() {
          _recommendations = rec;
          _isRegenerating = false;
        });
        return;
      }
    }

    if (mounted) {
      setState(() => _isRegenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Regenerating in background — pull to refresh in a moment.'),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
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
          'Recommendations',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Regenerate now',
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
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
            )
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final rec = _recommendations;

    if (rec == null || rec.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: Colors.white.withValues(alpha: 0.2),
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'No recommendations yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Recommendations are generated automatically after your first detection. Run a scan to get started.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF64748B), fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
      );
    }

    final sorted = rec.sortedByPriority;
    final generatedDate = _formatDate(rec.generatedAt);

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF3B82F6),
      backgroundColor: const Color(0xFF1E293B),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          // ── Generated date ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: Text(
              'Generated $generatedDate · refreshes daily',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
          ),

          // ── Recommendation cards ────────────────────────────────────────
          ...sorted.map((item) => _buildCard(item)),
        ],
      ),
    );
  }

  Widget _buildCard(RecommendationItem item) {
    final isUrgent = item.isUrgent;
    final accentColor =
        isUrgent ? const Color(0xFFEAB308) : const Color(0xFF3B82F6);
    final priorityLabel = isUrgent ? 'PRIORITY ${item.priority}  ·  URGENT' : 'PRIORITY ${item.priority}';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Priority + category row
                Row(
                  children: [
                    Icon(item.categoryIcon, color: accentColor, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      priorityLabel,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _categoryLabel(item.category),
                        style: TextStyle(
                          color: accentColor.withValues(alpha: 0.9),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Title
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),

                const SizedBox(height: 12),

                // Action section
                if (item.action.isNotEmpty) ...[
                  const Text(
                    'WHAT TO DO',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.action,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Reason section
                if (item.reason.isNotEmpty) ...[
                  const Text(
                    'WHY THIS MATTERS',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.reason,
                    style: TextStyle(
                      color: accentColor.withValues(alpha: 0.8),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Colored left border
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: accentColor,
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

  String _categoryLabel(String category) {
    const labels = {
      'rooster_health': 'Rooster Health',
      'flock_management': 'Flock Mgmt',
      'incubator': 'Incubator',
      'egg_handling': 'Egg Handling',
      'monitoring': 'Monitoring',
      'general': 'General',
    };
    return labels[category] ?? category;
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}
