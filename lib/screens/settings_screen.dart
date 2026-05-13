import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/summary_service.dart';
import '../services/user_settings_service.dart';
import 'tutorial_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _trendWindowDays = 14;
  int _summaryDayOfWeek = 1; // 1 = Monday … 7 = Sunday (DateTime.weekday)
  int _analysisHour = 21;
  int _analysisMinute = 0;
  bool _isRegeneratingSummary = false;

  static const List<String> _dayLabels = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    // Load local prefs first (instant) so UI shows correct values immediately.
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _trendWindowDays = prefs.getInt('trend_window_days') ?? 14;
        _summaryDayOfWeek = prefs.getInt('summary_day_of_week') ?? 1;
        _analysisHour = prefs.getInt('analysis_hour') ?? 21;
        _analysisMinute = prefs.getInt('analysis_minute') ?? 0;
      });
    }

    // If no local analysis time saved yet, fetch from backend as fallback.
    if (prefs.getInt('analysis_hour') == null) {
      final backendTime = await UserSettingsService().getAnalysisTime();
      if (mounted) {
        setState(() {
          _analysisHour = backendTime.hour;
          _analysisMinute = backendTime.minute;
        });
      }
    }
  }

  Future<void> _setTrendWindow(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('trend_window_days', days);
    if (mounted) setState(() => _trendWindowDays = days);
  }

  Future<void> _setSummaryDay(int day) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('summary_day_of_week', day);
    if (mounted) setState(() => _summaryDayOfWeek = day);
  }

  Future<void> _pickAnalysisTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _analysisHour, minute: _analysisMinute),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF3B82F6),
            surface: Color(0xFF1E293B),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('analysis_hour', picked.hour);
    await prefs.setInt('analysis_minute', picked.minute);
    if (mounted) {
      setState(() {
        _analysisHour = picked.hour;
        _analysisMinute = picked.minute;
      });
    }
    // Await backend save — was fire-and-forget before, which could leave the
    // server using stale default values (21:00) while the UI showed the new time.
    await UserSettingsService().setAnalysisTime(picked.hour, picked.minute);
  }

  String _formatAnalysisTime() {
    final h = _analysisHour % 12 == 0 ? 12 : _analysisHour % 12;
    final m = _analysisMinute.toString().padLeft(2, '0');
    final period = _analysisHour < 12 ? 'AM' : 'PM';
    return '$h:$m $period PKT';
  }

  /// Force-regenerate the latest weekly summary. Same backend endpoint used by
  /// the refresh icon inside the summary bottom sheet — keeps the existing
  /// weekStart/weekEnd, just refreshes the AI content. The new doc has
  /// isRead=false so the banner reappears on the dashboard.
  Future<void> _regenerateSummary() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Regenerate Weekly Summary?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will replace your most recent weekly summary with a fresh AI-written one '
          'covering the same week. The week boundaries stay the same and your next '
          'scheduled summary day is not affected.',
          style: TextStyle(color: Color(0xFF94A3B8), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text(
              'Regenerate',
              style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isRegeneratingSummary = true);
    final newSummary = await SummaryService().forceRegenerate();
    if (!mounted) return;
    setState(() => _isRegeneratingSummary = false);

    final messenger = ScaffoldMessenger.of(context);
    if (newSummary != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Summary regenerated for ${newSummary.formattedWeekRange}. '
            'Go to home screen to view it.',
          ),
          backgroundColor: const Color(0xFF22C55E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: const Text(
            'Could not regenerate. Either no prior summary exists yet, or the '
            'backend is unreachable. Check your connection and try again.',
          ),
          backgroundColor: const Color(0xFFEF4444),
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
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Trend window ───────────────────────────────────────────────
            const Text(
              'TREND ANALYSIS WINDOW',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'How many days of detection data to include in trend analysis.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [7, 14, 30].map((days) {
                  final isSelected = _trendWindowDays == days;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _setTrendWindow(days),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF94A3B8),
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 28),

            // ── Summary day ────────────────────────────────────────────────
            const Text(
              'WEEKLY SUMMARY DAY',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'The app generates a weekly performance summary on this day each week.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: List.generate(7, (i) {
                  final day = i + 1; // 1–7
                  final isSelected = _summaryDayOfWeek == day;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _setSummaryDay(day),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF3B82F6)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _dayLabels[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF94A3B8),
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            const SizedBox(height: 28),

            // ── Daily analysis time ────────────────────────────────────────
            const Text(
              'DAILY ANALYSIS TIME',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Trends and recommendations are generated once daily at this time (PKT).',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _pickAnalysisTime,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, color: Color(0xFF3B82F6), size: 20),
                    const SizedBox(width: 12),
                    Text(
                      _formatAnalysisTime(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right, color: Color(0xFF64748B), size: 20),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── Weekly Summary controls ────────────────────────────────────
            const Text(
              'WEEKLY SUMMARY',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Refresh the AI review for the current weekly summary. '
              'Useful if you dismissed the banner or want a freshly written analysis '
              'of the same week. Your scheduled summary day is unchanged.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _isRegeneratingSummary ? null : _regenerateSummary,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    _isRegeneratingSummary
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFF3B82F6),
                            ),
                          )
                        : const Icon(
                            Icons.refresh_rounded,
                            color: Color(0xFF3B82F6),
                            size: 20,
                          ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isRegeneratingSummary
                            ? 'Regenerating…'
                            : 'Regenerate Latest Weekly Summary',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (!_isRegeneratingSummary)
                      const Icon(Icons.chevron_right, color: Color(0xFF64748B), size: 20),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── Help & Tutorial ────────────────────────────────────────────
            const Text(
              'HELP & TUTORIAL',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TutorialScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.menu_book_outlined, color: Color(0xFF3B82F6), size: 20),
                    SizedBox(width: 12),
                    Text(
                      'App Tutorial for Hatcheries',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Spacer(),
                    Icon(Icons.chevron_right, color: Color(0xFF64748B), size: 20),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── About ──────────────────────────────────────────────────────
            const Text(
              'ABOUT',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF94A3B8), size: 20),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PoulTech AI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Version 1.0',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
