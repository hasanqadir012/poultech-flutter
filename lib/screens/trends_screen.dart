import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/daily_stat_model.dart';
import '../models/today_live_model.dart';
import '../models/trend_model.dart';
import '../services/trend_service.dart';

class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key});

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  final TrendService _trendService = TrendService();

  int _windowDays = 14;
  TrendModel? _latestTrend;
  List<DailyStatModel> _dailyStats = [];
  TodayLiveModel? _todayLive;
  List<TrendModel> _trendHistory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWindowPreference().then((_) => _loadData());
  }

  Future<void> _loadWindowPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _windowDays = prefs.getInt('trend_window_days') ?? 14);
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final results = await Future.wait([
      _trendService.getLatestTrend(windowDays: _windowDays),
      _trendService.getDailyStats(days: _windowDays),
      _trendService.getTodayLive(),
      _trendService.getTrendHistory(),
    ]);

    if (mounted) {
      setState(() {
        _latestTrend = results[0] as TrendModel?;
        _dailyStats = results[1] as List<DailyStatModel>;
        _todayLive = results[2] as TodayLiveModel?;
        _trendHistory = results[3] as List<TrendModel>;
        _isLoading = false;
      });
    }
  }

  Future<void> _setWindow(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('trend_window_days', days);
    if (mounted) setState(() => _windowDays = days);
    await _loadData();
  }

  // Today's date in PKT (UTC+5) as "YYYY-MM-DD"
  String get _todayPktDate {
    final nowPkt = DateTime.now().toUtc().add(const Duration(hours: 5));
    return '${nowPkt.year}-${nowPkt.month.toString().padLeft(2, '0')}-${nowPkt.day.toString().padLeft(2, '0')}';
  }

  // True if today's official daily_stats doc is already in the list
  bool get _isTodayInDailyStats =>
      _dailyStats.isNotEmpty && _dailyStats.last.date == _todayPktDate;

  // Show live dot only when today has detections but analysis hasn't run yet
  bool get _shouldShowLiveDot =>
      (_todayLive?.hasData ?? false) && !_isTodayInDailyStats;

  // All chart spots: one per daily_stat + optional live today dot
  List<FlSpot> get _chartSpots {
    final spots = <FlSpot>[];
    for (var i = 0; i < _dailyStats.length; i++) {
      spots.add(FlSpot(i.toDouble(), _dailyStats[i].averageFertilityRate * 100));
    }
    return spots;
  }

  FlSpot? get _liveSpot {
    if (!_shouldShowLiveDot) return null;
    return FlSpot(
      _dailyStats.length.toDouble(),
      _todayLive!.averageFertilityRate * 100,
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
          'Trend Analysis',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF3B82F6)))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: const Color(0xFF3B82F6),
              backgroundColor: const Color(0xFF1E293B),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWindowSelector(),
                    const SizedBox(height: 20),
                    _buildSummaryCard(),
                    const SizedBox(height: 20),
                    if (_shouldShowLiveDot) ...[
                      _buildTodayLiveCard(),
                      const SizedBox(height: 12),
                    ],
                    _buildChart(),
                    const SizedBox(height: 20),
                    _buildHistorySection(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  // ── Window selector ────────────────────────────────────────────────────────

  Widget _buildWindowSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [7, 14, 30].map((days) {
          final isSelected = _windowDays == days;
          return Expanded(
            child: GestureDetector(
              onTap: () => _setWindow(days),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF3B82F6)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$days Days',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color:
                        isSelected ? Colors.white : const Color(0xFF94A3B8),
                    fontSize: 14,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Summary card ───────────────────────────────────────────────────────────

  Widget _buildSummaryCard() {
    if (_latestTrend == null || _dailyStats.isEmpty) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.show_chart, color: Color(0xFF64748B), size: 20),
                SizedBox(width: 8),
                Text(
                  'No Trend Data Yet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _dailyStats.isEmpty
                  ? 'Trend analysis generates once daily at your scheduled analysis time. Run detections today to get started.'
                  : 'Run detections on at least 2 separate days to see trend direction.',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14, height: 1.5),
            ),
          ],
        ),
      );
    }

    final t = _latestTrend!;
    final color = t.trendColor;

    return Stack(
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(t.trendIcon, color: color, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        t.trendLabel,
                        style: TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'Avg ${t.averagePercent}',
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (!t.hasInsufficientData) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    _statChip('High',
                        '${(t.highestRate * 100).toStringAsFixed(0)}%',
                        const Color(0xFF22C55E)),
                    const SizedBox(width: 8),
                    _statChip('Low',
                        '${(t.lowestRate * 100).toStringAsFixed(0)}%',
                        const Color(0xFFEF4444)),
                    const SizedBox(width: 8),
                    _statChip('Days', '${t.windowDays}',
                        const Color(0xFF3B82F6)),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Text(
                t.agentSummary,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Based on ${t.reportCount} total detections across ${t.windowDays} days',
                style: const TextStyle(color: Color(0xFF475569), fontSize: 11),
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

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
                color: color, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
          ),
        ],
      ),
    );
  }

  // ── Today Live card ────────────────────────────────────────────────────────

  Widget _buildTodayLiveCard() {
    final live = _todayLive!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF3B82F6), width: 2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TODAY (LIVE)',
                  style: TextStyle(
                    color: Color(0xFF3B82F6),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${live.detectionCount} detection${live.detectionCount == 1 ? '' : 's'} · Running avg ${live.averagePercent}',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const Text(
            'Full analysis\nruns at scheduled time',
            textAlign: TextAlign.right,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 10, height: 1.4),
          ),
        ],
      ),
    );
  }

  // ── Line chart ─────────────────────────────────────────────────────────────

  Widget _buildChart() {
    final historicalSpots = _chartSpots;
    final live = _liveSpot;
    final trendColor = _latestTrend?.trendColor ?? const Color(0xFF3B82F6);
    final totalPoints = historicalSpots.length + (live != null ? 1 : 0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DAILY FERTILITY RATE',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 16),
          if (historicalSpots.isEmpty && live == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    const Icon(Icons.show_chart, color: Color(0xFF334155), size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'No daily data in the last $_windowDays days',
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Chart updates once daily at your analysis time.',
                      style: TextStyle(color: Color(0xFF475569), fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minX: -0.5,
                  maxX: (totalPoints - 1).toDouble() + 0.5,
                  minY: 0,
                  maxY: 100,
                  lineBarsData: [
                    // Historical solid line
                    if (historicalSpots.isNotEmpty)
                      LineChartBarData(
                        spots: historicalSpots,
                        isCurved: historicalSpots.length > 2,
                        color: trendColor,
                        barWidth: 2.5,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, bar, index) =>
                              FlDotCirclePainter(
                            radius: 4,
                            color: trendColor,
                            strokeWidth: 2,
                            strokeColor: const Color(0xFF1E293B),
                          ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          color: trendColor.withValues(alpha: 0.08),
                        ),
                      ),
                    // Live dot — hollow, no connecting line
                    if (live != null)
                      LineChartBarData(
                        spots: [live],
                        isCurved: false,
                        color: Colors.transparent,
                        barWidth: 0,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, bar, index) =>
                              FlDotCirclePainter(
                            radius: 5,
                            color: const Color(0xFF1E293B),
                            strokeWidth: 2.5,
                            strokeColor: const Color(0xFF3B82F6),
                          ),
                        ),
                      ),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: 25,
                        getTitlesWidget: (value, meta) => Text(
                          '${value.toInt()}%',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (value, meta) {
                          final idx = value.round();
                          if (idx < 0 || idx >= _dailyStats.length) return const SizedBox.shrink();
                          // Show label only for first, middle, last
                          final showAt = {0, _dailyStats.length ~/ 2, _dailyStats.length - 1};
                          if (!showAt.contains(idx)) return const SizedBox.shrink();
                          return Text(
                            _dailyStats[idx].dateLabel,
                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 25,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: Colors.white.withValues(alpha: 0.05),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          if (_dailyStats.isNotEmpty || live != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (_dailyStats.isNotEmpty) ...[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: trendColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_dailyStats.length} day${_dailyStats.length == 1 ? '' : 's'} of data',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  ),
                ],
                if (live != null) ...[
                  const SizedBox(width: 14),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF3B82F6), width: 2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Today (live)',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Trend history ──────────────────────────────────────────────────────────

  Widget _buildHistorySection() {
    if (_trendHistory.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TREND HISTORY',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        ..._trendHistory.take(10).map(_buildHistoryItem),
      ],
    );
  }

  Widget _buildHistoryItem(TrendModel t) {
    final color = t.trendColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          Icon(t.trendIcon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.trendLabel,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${t.windowDays} days · ${t.reportCount} total detections',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                t.averagePercent,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _fmtDate(t.generatedAt),
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: child,
    );
  }

  String _fmtDate(DateTime dt) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${m[dt.month - 1]} ${dt.day}';
  }
}
