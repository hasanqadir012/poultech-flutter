import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/batch_model.dart';
import '../models/recommendation_model.dart';
import '../models/summary_model.dart';
import '../models/trend_model.dart';
import '../providers/auth_provider.dart';
import '../services/batch_service.dart';
import '../services/recommendation_service.dart';
import '../services/summary_service.dart';
import '../services/trend_service.dart';
import 'batch_screen.dart';
import 'knowledge_assistant.dart';
import 'recommendations_screen.dart';
import 'report_history.dart';
import 'settings_screen.dart';
import 'trends_screen.dart';
import 'upload_screen.dart';

enum _SummaryBadge { sample, fresh, current, previous }

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard>
    with SingleTickerProviderStateMixin {
  // Services
  final BatchService _batchService = BatchService();
  final TrendService _trendService = TrendService();
  final RecommendationService _recommendationService = RecommendationService();
  final SummaryService _summaryService = SummaryService();

  // Data state
  bool _isLoading = true;
  BatchModel? _activeBatch;
  TrendModel? _latestTrend;
  RecommendationsModel? _latestRecommendations;
  SummaryModel? _latestSummary;
  bool _summaryDismissed = false;
  int _trendWindowDays = 14;

  // Skeleton pulse animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadAll();
    // Non-blocking: generates weekly summary if today is the configured day
    SummaryService().checkAndGenerateWeeklySummary().catchError((_) {});
    // Non-blocking: triggers daily analysis if past scheduled time and not yet run today
    TrendService().triggerDailyAnalysis().catchError((_) {});
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _trendWindowDays = prefs.getInt('trend_window_days') ?? 14;
      _isLoading = true;
    });

    final results = await Future.wait([
      _safe(() => _batchService.getActiveBatch()),
      _safe(() => _trendService.getLatestTrend(windowDays: _trendWindowDays)),
      _safe(() => _recommendationService.getLatestRecommendations()),
      _safe(() => _summaryService.getLatestSummary()),
    ]);

    if (mounted) {
      setState(() {
        _activeBatch = results[0] as BatchModel?;
        _latestTrend = results[1] as TrendModel?;
        _latestRecommendations = results[2] as RecommendationsModel?;
        _latestSummary = results[3] as SummaryModel?;
        _isLoading = false;
      });
    }
  }

  Future<Object?> _safe(Future<Object?> Function() fn) async {
    try {
      return await fn();
    } catch (_) {
      return null;
    }
  }

  // Lightweight batch-only refresh used after closing a batch
  Future<void> _refreshBatch() async {
    final batch = await _safe(() => _batchService.getActiveBatch());
    if (mounted) setState(() => _activeBatch = batch as BatchModel?);
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _navigateToBatchScreen() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const BatchScreen()))
        .then((_) => _loadAll());
  }

  void _navigateTo(Widget screen) {
    Navigator.of(context)
        .push(PageRouteBuilder(
          pageBuilder: (_, animation, __) => screen,
          transitionsBuilder: (_, animation, __, child) {
            const begin = Offset(1.0, 0.0);
            const curve = Curves.easeInOut;
            final tween =
                Tween(begin: begin, end: Offset.zero).chain(CurveTween(curve: curve));
            return SlideTransition(position: animation.drive(tween), child: child);
          },
          transitionDuration: const Duration(milliseconds: 300),
        ))
        .then((_) => _loadAll());
  }

  // ── Computed state ─────────────────────────────────────────────────────────

  bool get _isNewUser =>
      (_latestTrend == null || _latestTrend!.hasInsufficientData) &&
      _latestRecommendations == null &&
      _latestSummary == null;

  _SummaryBadge get _summaryBadge {
    final s = _latestSummary;
    if (s == null) return _SummaryBadge.sample;
    final ageDays = DateTime.now().difference(s.generatedAt).inDays;
    if (ageDays <= 2 && s.isCurrentPeriod) return _SummaryBadge.fresh;
    if (s.isCurrentPeriod) return _SummaryBadge.current;
    return _SummaryBadge.previous;
  }

  bool get _shouldShowSummary {
    if (_summaryDismissed) return false;
    final s = _latestSummary;
    if (s == null) return false;
    // Note: s.isRead is intentionally ignored. Dismiss is session-only — the
    // banner reappears on next app open until the next week's summary
    // naturally supersedes this one. (Old behaviour permanently hid summaries
    // after one Dismiss tap, which was hostile UX.)
    return true;
  }

  // Show sample only when no real summary has ever been generated for this user
  bool get _shouldShowSampleSummary =>
      !_isLoading && !_summaryDismissed && _latestSummary == null;

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadAll,
                  color: const Color(0xFF3B82F6),
                  backgroundColor: const Color(0xFF1E293B),
                  child: _isLoading
                      ? _buildSkeletonLayout()
                      : _buildContent(),
                ),
              ),
              _buildPinnedActions(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Main content (shown when not loading) ──────────────────────────────────

  Widget _buildContent() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),

          // ── Batch status (always visible) ──────────────────────────────
          _buildBatchStatusCard(),
          const SizedBox(height: 12),

          // ── Weekly summary banner ─────────────────────────────────────
          if (_shouldShowSummary) ...[
            _buildWeeklySummaryBanner(_latestSummary!, badge: _summaryBadge),
            const SizedBox(height: 12),
          ] else if (_shouldShowSampleSummary) ...[
            _buildWeeklySummaryBanner(_sampleSummary(), badge: _SummaryBadge.sample),
            const SizedBox(height: 12),
          ],

          // ── New user empty state vs. intelligence sections ──────────────
          if (_isNewUser)
            _buildGettingStartedCard()
          else ...[
            _sectionLabel('TRENDS'),
            const SizedBox(height: 8),
            _buildTrendCard(),
            const SizedBox(height: 16),
            _buildRecommendationsSection(),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Skeleton loading ───────────────────────────────────────────────────────

  Widget _buildSkeletonLayout() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, _) {
          return Column(
            children: [
              _skeletonCard(76),
              const SizedBox(height: 12),
              _skeletonCard(56),
              const SizedBox(height: 12),
              _skeletonCard(104),
              const SizedBox(height: 12),
              _skeletonCard(144),
            ],
          );
        },
      ),
    );
  }

  Widget _skeletonCard(double height) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Color.lerp(
          const Color(0xFF1E293B),
          const Color(0xFF2D3F55),
          _pulseAnimation.value,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  // ── Getting Started (empty state for new users) ────────────────────────────

  Widget _buildGettingStartedCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.egg_alt_outlined, color: Color(0xFF3B82F6), size: 22),
              SizedBox(width: 10),
              Text(
                'Getting Started',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Run your first detection to unlock:',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          const SizedBox(height: 12),
          _gettingStartedItem('Trend analysis — see fertility patterns over time'),
          _gettingStartedItem('AI recommendations — targeted actions for your farm'),
          _gettingStartedItem('Weekly summaries — regular performance reviews'),
        ],
      ),
    );
  }

  Widget _gettingStartedItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.check_circle_outline,
              color: Color(0xFF3B82F6),
              size: 14,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section label ──────────────────────────────────────────────────────────

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

  // ── Pinned action buttons ──────────────────────────────────────────────────

  Widget _buildPinnedActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: [
          Expanded(
            child: _actionButton(
              Icons.egg_outlined,
              'Detect',
              [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)],
              () => _navigateTo(const ImageUploadScreen()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _actionButton(
              Icons.description_outlined,
              'Reports',
              [const Color(0xFF10B981), const Color(0xFF059669)],
              () => _navigateTo(const ReportHistoryScreen()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _actionButton(
              Icons.psychology_outlined,
              'Assistant',
              [const Color(0xFFA855F7), const Color(0xFF9333EA)],
              () => _navigateTo(const KnowledgeAssistantScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    IconData icon,
    String label,
    List<Color> colors,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Close batch confirmation ────────────────────────────────────────────────

  Future<void> _confirmCloseBatch(BatchModel batch) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        decoration: const BoxDecoration(
          color: Color(0xFF1E293B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Close "${batch.name}"?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You can create a new batch anytime.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFF334155),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFFEF4444),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Close Batch',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final success = await _batchService.closeBatch(batch.id);
    if (mounted) {
      if (success) {
        _refreshBatch();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${batch.name}" closed.'),
            backgroundColor: const Color(0xFF22C55E),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to close batch. Check your connection.'),
            backgroundColor: Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Batch Status Card ──────────────────────────────────────────────────────

  Widget _buildBatchStatusCard() {
    if (_activeBatch != null) {
      return Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.circle,
                              color: Color(0xFF22C55E), size: 8),
                          SizedBox(width: 8),
                          Text(
                            'ACTIVE BATCH',
                            style: TextStyle(
                              color: Color(0xFF22C55E),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _activeBatch!.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Started ${_activeBatch!.formattedDate} · '
                        '${_activeBatch!.totalDetections} '
                        'detection${_activeBatch!.totalDetections == 1 ? '' : 's'} so far',
                        style: const TextStyle(
                            color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => _confirmCloseBatch(_activeBatch!),
                  style: TextButton.styleFrom(
                    backgroundColor:
                        const Color(0xFFEF4444).withValues(alpha: 0.1),
                    foregroundColor: const Color(0xFFEF4444),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                          color:
                              const Color(0xFFEF4444).withValues(alpha: 0.3)),
                    ),
                  ),
                  child: const Text(
                    'Close',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
              decoration: const BoxDecoration(
                color: Color(0xFF22C55E),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // No active batch — amber warning card
    return GestureDetector(
      onTap: _navigateToBatchScreen,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Color(0xFFF97316), size: 14),
                          SizedBox(width: 6),
                          Text(
                            'NO ACTIVE BATCH',
                            style: TextStyle(
                              color: Color(0xFFF97316),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Create a batch to organize detections and enable AI trend analysis',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFFF97316).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color:
                            const Color(0xFFF97316).withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Start',
                        style: TextStyle(
                          color: Color(0xFFF97316),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward,
                          color: Color(0xFFF97316), size: 14),
                    ],
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
              decoration: const BoxDecoration(
                color: Color(0xFFF97316),
                borderRadius: BorderRadius.only(
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

  // ── Trend Card ────────────────────────────────────────────────────────────

  Widget _buildTrendCard() {
    final trend = _latestTrend;

    // Case 1: No trend at all — user has zero detections (or daily_stats failed).
    // Show a generic "get started" placeholder that's still tappable.
    if (trend == null) {
      return GestureDetector(
        onTap: () => _navigateTo(const TrendsScreen()),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: const Row(
            children: [
              Icon(Icons.show_chart, color: Color(0xFF64748B), size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trend Analysis',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Detect on 2+ separate days to see trend direction. Tap to view today\'s live chart.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.chevron_right, color: Color(0xFF64748B), size: 20),
            ],
          ),
        ),
      );
    }

    // Case 2: Day-1 baseline — we have ONE day of data. Trend direction is
    // mathematically impossible (need >=2 points for a slope), but we can
    // still show today's average + count so the card isn't blank.
    if (trend.hasInsufficientData) {
      final accent = const Color(0xFF3B82F6);
      return GestureDetector(
        onTap: () => _navigateTo(const TrendsScreen()),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.timeline_outlined, color: accent, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BUILDING TREND · DAY 1 OF 2',
                      style: TextStyle(
                        color: accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          trend.averagePercent,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'avg · ${trend.reportCount} detection${trend.reportCount == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Detect again tomorrow to unlock trend direction.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Color(0xFF64748B), size: 20),
            ],
          ),
        ),
      );
    }

    final t = _latestTrend!;
    final color = t.trendColor;

    return GestureDetector(
      onTap: () => _navigateTo(const TrendsScreen()),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.show_chart, color: color, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            '${t.windowDays}-DAY TREND',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(t.trendIcon, color: color, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            t.trendLabel,
                            style: TextStyle(
                              color: color,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Avg ${t.averagePercent}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: color.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View',
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward, color: color, size: 12),
                    ],
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
      ),
    );
  }

  // ── Weekly Summary Card ────────────────────────────────────────────────────

  static SummaryModel _sampleSummary() {
    final now = DateTime.now();
    return SummaryModel(
      id: '__sample__',
      userId: '',
      weekStart: now.subtract(const Duration(days: 7)),
      weekEnd: now.subtract(const Duration(days: 1)),
      generatedAt: now,
      reportCount: 34,
      totalEggsAnalyzed: 1700,
      totalFertileEggs: 1394,
      totalInfertileEggs: 306,
      averageFertilityRate: 0.82,
      highestFertilityRate: 0.91,
      lowestFertilityRate: 0.71,
      bestBatchLabel: 'Batch A-3',
      worstBatchLabel: 'Batch B-7',
      batchesActive: 4,
      agentSummary:
          'This is a preview of your upcoming weekly summary. Once you have run '
          'detections for a full week, your personalized AI performance review will appear here — '
          'covering your hatchery\'s fertility trends, top and lowest-performing batches, '
          'and targeted improvement recommendations. '
          'Run daily detections to build your data; your first real summary will appear '
          'automatically on your configured summary day.',
      isRead: false,
    );
  }

  // ── Weekly Summary — compact banner on dashboard ───────────────────────────

  Widget _buildWeeklySummaryBanner(SummaryModel s, {_SummaryBadge badge = _SummaryBadge.current}) {
    final (badgeLabel, badgeColor) = switch (badge) {
      _SummaryBadge.sample   => ('SAMPLE · TAP TO PREVIEW', const Color(0xFFF97316)),
      _SummaryBadge.fresh    => ('NEW THIS WEEK', const Color(0xFF22C55E)),
      _SummaryBadge.current  => ('WEEKLY SUMMARY READY', const Color(0xFF3B82F6)),
      _SummaryBadge.previous => ('PREVIOUS WEEK', const Color(0xFF64748B)),
    };

    return GestureDetector(
      onTap: () => _showSummaryBottomSheet(s, isSample: badge == _SummaryBadge.sample),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                badge == _SummaryBadge.sample
                    ? Icons.preview_outlined
                    : Icons.summarize_outlined,
                color: badgeColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    badgeLabel,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    s.formattedWeekRange,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    badge == _SummaryBadge.sample
                        ? 'Sample data · See how your summary will look'
                        : '${s.reportCount} detections · ${s.totalEggsAnalyzed} eggs · Avg ${s.averagePercent}',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Color(0xFF64748B),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  // ── Weekly Summary — full bottom sheet ────────────────────────────────────

  void _showSummaryBottomSheet(SummaryModel s, {bool isSample = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SummaryBottomSheet(
        summary: s,
        isSample: isSample,
        onDismiss: isSample
            ? null
            : () {
                // Session-only dismiss — DO NOT call markRead. The banner
                // hides until app restart, after which it returns. The next
                // week's summary will naturally replace it via /summaries/latest.
                if (mounted) setState(() => _summaryDismissed = true);
              },
        // Sample summaries can't be regenerated — they aren't in the DB.
        onRegenerate: isSample
            ? null
            : () async {
                final regenerated = await _summaryService.forceRegenerate();
                if (regenerated != null && mounted) {
                  setState(() => _latestSummary = regenerated);
                }
                return regenerated;
              },
      ),
    );
  }

  // ── Recommendations Badge Card ─────────────────────────────────────────────

  Widget _buildRecommendationsSection() {
    final rec = _latestRecommendations;
    if (rec == null || rec.items.isEmpty) return const SizedBox.shrink();

    final count = rec.items.length;
    final hasUrgent = rec.items.any((i) => i.isUrgent);
    final accentColor =
        hasUrgent ? const Color(0xFFEAB308) : const Color(0xFF3B82F6);
    final topItem = rec.sortedByPriority.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('RECOMMENDATIONS'),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _navigateTo(const RecommendationsScreen()),
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(topItem.categoryIcon,
                                  color: accentColor, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                hasUrgent ? 'URGENT ACTION NEEDED' : 'REVIEW RECOMMENDED',
                                style: TextStyle(
                                  color: accentColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            topItem.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$count recommendation${count == 1 ? '' : 's'} · Tap to view all',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: accentColor,
                        size: 18,
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
        ),
      ],
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PoulTech AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Welcome, ${auth.displayName}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Your hatchery intelligence dashboard',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            children: [
              _headerIconButton(
                Icons.settings_outlined,
                () => _navigateTo(const SettingsScreen()),
              ),
              const SizedBox(width: 8),
              _headerIconButton(
                Icons.logout_rounded,
                () async {
                  final auth = context.read<AppAuthProvider>();
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF1E293B),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      title: const Text('Sign Out?',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      content: const Text(
                          'You will be returned to the login screen.',
                          style: TextStyle(color: Color(0xFF94A3B8))),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel',
                              style: TextStyle(
                                  color: Color(0xFF64748B))),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Sign Out',
                              style: TextStyle(
                                  color: Color(0xFFEF4444))),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) await auth.signOut();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Icon(icon,
            color: Colors.white.withValues(alpha: 0.7), size: 20),
      ),
    );
  }
}

// ── Weekly Summary Bottom Sheet ───────────────────────────────────────────────

class _SummaryBottomSheet extends StatefulWidget {
  final SummaryModel summary;
  final bool isSample;
  final VoidCallback? onDismiss;
  // Returns the freshly regenerated summary (or null on failure / no data).
  // Parent is responsible for updating its own state if needed.
  final Future<SummaryModel?> Function()? onRegenerate;

  const _SummaryBottomSheet({
    required this.summary,
    this.isSample = false,
    this.onDismiss,
    this.onRegenerate,
  });

  @override
  State<_SummaryBottomSheet> createState() => _SummaryBottomSheetState();
}

class _SummaryBottomSheetState extends State<_SummaryBottomSheet> {
  late SummaryModel _summary;
  bool _isRegenerating = false;

  @override
  void initState() {
    super.initState();
    _summary = widget.summary;
  }

  Future<void> _handleRegenerate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Regenerate Summary?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will replace the AI review for ${_summary.formattedWeekRange} '
          'with a fresh one for the same week. The week dates and your '
          'next scheduled summary day are not affected.',
          style: const TextStyle(color: Color(0xFF94A3B8)),
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

    setState(() => _isRegenerating = true);
    final newSummary = await widget.onRegenerate?.call();
    if (!mounted) return;

    if (newSummary != null) {
      setState(() {
        _summary = newSummary;
        _isRegenerating = false;
      });
    } else {
      setState(() => _isRegenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Regeneration failed. Check the backend logs.'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    final isSample = widget.isSample;
    final onDismiss = widget.onDismiss;
    final canRegenerate = !isSample && widget.onRegenerate != null;
    final avgColor = s.averageFertilityRate >= 0.65
        ? const Color(0xFF22C55E)
        : s.averageFertilityRate >= 0.50
            ? const Color(0xFFF97316)
            : const Color(0xFFEF4444);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isSample)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF97316).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFF97316).withValues(alpha: 0.4)),
                            ),
                            child: const Text(
                              'SAMPLE PREVIEW',
                              style: TextStyle(
                                color: Color(0xFFF97316),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        Text(
                          isSample ? 'Sample Weekly Summary' : 'Weekly Summary',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.formattedWeekRange,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canRegenerate) ...[
                    GestureDetector(
                      onTap: _isRegenerating ? null : _handleRegenerate,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF334155),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _isRegenerating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF3B82F6),
                                ),
                              )
                            : const Icon(
                                Icons.refresh_rounded,
                                color: Color(0xFF94A3B8),
                                size: 18,
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      if (!isSample) onDismiss?.call();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isSample ? 'Got it' : 'Dismiss',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Divider(color: Color(0xFF1E293B), height: 1),

            // Scrollable content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  // ── Sample notice ──────────────────────────────────────
                  if (isSample) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF97316).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF97316).withValues(alpha: 0.25)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Color(0xFFF97316), size: 15),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This is a preview using sample data. Your real summary replaces it once generated.',
                              style: TextStyle(
                                color: Color(0xFFF97316),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // ── At-a-glance stats row ──────────────────────────────
                  Row(
                    children: [
                      _statChip(
                        label: 'Detections',
                        value: '${s.reportCount}',
                        color: const Color(0xFF3B82F6),
                      ),
                      const SizedBox(width: 10),
                      _statChip(
                        label: 'Eggs',
                        value: '${s.totalEggsAnalyzed}',
                        color: const Color(0xFF3B82F6),
                      ),
                      const SizedBox(width: 10),
                      _statChip(
                        label: 'Avg Rate',
                        value: s.averagePercent,
                        color: avgColor,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Fertility breakdown ────────────────────────────────
                  _sectionHeader('FERTILITY BREAKDOWN'),
                  const SizedBox(height: 10),
                  _detailCard(children: [
                    _statRow(Icons.check_circle_outline,
                        const Color(0xFF22C55E), 'Fertile eggs',
                        '${s.totalFertileEggs}'),
                    const SizedBox(height: 10),
                    _statRow(Icons.cancel_outlined,
                        const Color(0xFFEF4444), 'Infertile eggs',
                        '${s.totalInfertileEggs}'),
                    const SizedBox(height: 10),
                    _statRow(Icons.percent_rounded,
                        avgColor, 'Average fertility',
                        s.averagePercent),
                    if (s.batchesActive > 0) ...[
                      const SizedBox(height: 10),
                      _statRow(Icons.inventory_2_outlined,
                          const Color(0xFF94A3B8), 'Active batches',
                          '${s.batchesActive}'),
                    ],
                  ]),

                  const SizedBox(height: 20),

                  // ── Best & worst ───────────────────────────────────────
                  _sectionHeader('PERFORMANCE RANGE'),
                  const SizedBox(height: 10),
                  _detailCard(children: [
                    _statRow(
                      Icons.trending_up,
                      const Color(0xFF22C55E),
                      'Best detection',
                      s.bestBatchLabel != null
                          ? '${(s.highestFertilityRate * 100).toStringAsFixed(0)}%  ·  ${s.bestBatchLabel}'
                          : '${(s.highestFertilityRate * 100).toStringAsFixed(0)}%',
                    ),
                    const SizedBox(height: 10),
                    _statRow(
                      Icons.trending_down,
                      const Color(0xFFEF4444),
                      'Worst detection',
                      s.worstBatchLabel != null
                          ? '${(s.lowestFertilityRate * 100).toStringAsFixed(0)}%  ·  ${s.worstBatchLabel}'
                          : '${(s.lowestFertilityRate * 100).toStringAsFixed(0)}%',
                    ),
                  ]),

                  const SizedBox(height: 20),

                  // ── Agent summary ──────────────────────────────────────
                  _sectionHeader('AI PERFORMANCE REVIEW'),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Text(
                      s.agentSummary,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 14,
                        height: 1.65,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(
      {required String label, required String value, required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) {
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

  Widget _detailCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _statRow(IconData icon, Color color, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 10),
        Text(
          '$label:  ',
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
