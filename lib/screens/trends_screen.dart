import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/agent_analysis_model.dart';
import '../models/daily_stat_model.dart';
import '../models/today_live_model.dart';
import '../services/agent_analysis_service.dart';
import '../services/trend_service.dart';

class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key});

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  final TrendService _trendService = TrendService();
  final AgentAnalysisService _agentService = AgentAnalysisService();

  int _windowDays = 14;
  List<DailyStatModel> _dailyStats = [];
  TodayLiveModel? _todayLive;
  AgentAnalysisModel? _latestAgent;
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
      _trendService.getDailyStats(days: _windowDays),
      _trendService.getTodayLive(),
      _agentService.getLatest(),
    ]);

    if (mounted) {
      setState(() {
        _dailyStats = results[0] as List<DailyStatModel>;
        _todayLive = results[1] as TodayLiveModel?;
        _latestAgent = results[2] as AgentAnalysisModel?;
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

  String get _todayPktDate {
    final nowPkt = DateTime.now().toUtc().add(const Duration(hours: 5));
    return '${nowPkt.year}-${nowPkt.month.toString().padLeft(2, '0')}-${nowPkt.day.toString().padLeft(2, '0')}';
  }

  bool get _isTodayInDailyStats =>
      _dailyStats.isNotEmpty && _dailyStats.last.date == _todayPktDate;

  bool get _shouldShowLiveDot =>
      (_todayLive?.hasData ?? false) && !_isTodayInDailyStats;

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

  // Accent color — agent severity if known, else neutral blue
  Color get _accentColor => _latestAgent?.severity.color ?? const Color(0xFF3B82F6);

  // Derived stats from daily_stats — no longer reads from the legacy trends collection
  ({double avg, double high, double low, int totalDetections})? get _summary {
    if (_dailyStats.isEmpty) return null;
    final rates = _dailyStats.map((d) => d.averageFertilityRate).toList();
    final highs = _dailyStats.map((d) => d.highestRate).toList();
    final lows = _dailyStats.map((d) => d.lowestRate).toList();
    return (
      avg: rates.reduce((a, b) => a + b) / rates.length,
      high: highs.reduce((a, b) => a > b ? a : b),
      low: lows.reduce((a, b) => a < b ? a : b),
      totalDetections: _dailyStats.fold(0, (s, d) => s + d.detectionCount),
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
                  ],
                ),
              ),
            ),
    );
  }

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

  Widget _buildSummaryCard() {
    final s = _summary;
    final agent = _latestAgent;

    if (s == null) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.show_chart, color: Color(0xFF64748B), size: 20),
                SizedBox(width: 8),
                Text(
                  'No Daily Data Yet',
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
              _todayLive?.hasData ?? false
                  ? 'Today\'s detections are showing as a live dot below. The daily aggregate appears tomorrow.'
                  : 'Run detections to populate the chart. Daily averages aggregate at your analysis time.',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14, height: 1.5),
            ),
          ],
        ),
      );
    }

    final color = _accentColor;
    final avgPct = '${(s.avg * 100).toStringAsFixed(1)}%';

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
                      Icon(
                        agent?.severity.icon ?? Icons.show_chart,
                        color: color,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        agent != null
                            ? agent.severity.label.toUpperCase()
                            : '${_dailyStats.length}-DAY AVERAGE',
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
                      'Avg $avgPct',
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _statChip('High',
                      '${(s.high * 100).toStringAsFixed(0)}%',
                      const Color(0xFF22C55E)),
                  const SizedBox(width: 8),
                  _statChip('Low',
                      '${(s.low * 100).toStringAsFixed(0)}%',
                      const Color(0xFFEF4444)),
                  const SizedBox(width: 8),
                  _statChip('Days', '${_dailyStats.length}',
                      const Color(0xFF3B82F6)),
                ],
              ),
              if (agent != null && agent.trendNarrative.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  agent.trendNarrative,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'Based on ${s.totalDetections} total detection${s.totalDetections == 1 ? '' : 's'} across ${_dailyStats.length} day${_dailyStats.length == 1 ? '' : 's'}',
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

  Widget _buildChart() {
    final historicalSpots = _chartSpots;
    final live = _liveSpot;
    final color = _accentColor;
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
                    if (historicalSpots.isNotEmpty)
                      LineChartBarData(
                        spots: historicalSpots,
                        isCurved: historicalSpots.length > 2,
                        color: color,
                        barWidth: 2.5,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, bar, index) =>
                              FlDotCirclePainter(
                            radius: 4,
                            color: color,
                            strokeWidth: 2,
                            strokeColor: const Color(0xFF1E293B),
                          ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          color: color.withValues(alpha: 0.08),
                        ),
                      ),
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
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          if ((value - value.roundToDouble()).abs() > 0.01) {
                            return const SizedBox.shrink();
                          }
                          final idx = value.round();
                          if (idx < 0 || idx >= _dailyStats.length) return const SizedBox.shrink();
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
                      color: color,
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
}
