import 'package:flutter/material.dart';

class TutorialScreen extends StatelessWidget {
  const TutorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          'App Tutorial',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          const _TutorialSection(
            icon: Icons.camera_alt_outlined,
            title: 'Running a Detection',
            bullets: [
              'Tap the Upload button on the home screen to begin.',
              'Choose an image from your gallery or take a photo of the egg tray.',
              'Select detection mode: On-Device (fast, offline) or Cloud (Roboflow, more accurate).',
              'Results appear instantly — fertile and infertile eggs are highlighted with bounding boxes.',
              'Tap Save Report to store the result. Saved reports appear in Report History.',
            ],
          ),
          const _TutorialSection(
            icon: Icons.show_chart,
            title: 'Trends',
            bullets: [
              'The Trends screen shows a line chart of daily average fertility rate over time.',
              'Each dot on the chart = one full day of detections (not one detection).',
              'A hollow dot at the end of the line shows today\'s running average in real time.',
              'Use the 7 / 14 / 30 day selector to change how much history is shown.',
              'Historical data only appears after daily analysis runs at your scheduled time.',
            ],
          ),
          const _TutorialSection(
            icon: Icons.lightbulb_outline,
            title: 'Daily AI Recommendations',
            bullets: [
              'Recommendations are generated once per day by LLM.',
              'They are based on your recent detections and the day\'s trend.',
              'The dashboard shows a badge with the number of active recommendations.',
              'Tap the badge to open the full Recommendations screen.',
              'Each card explains what to do and why it matters for your hatchery.',
            ],
          ),
          _TutorialSection(
            icon: Icons.calendar_today_outlined,
            title: 'Weekly Summary',
            bullets: const [
              'A summary of your week\'s performance is generated on your chosen day each week.',
              'It covers total detections, average fertility rate, best and worst results.',
              'A banner appears on the dashboard — tap it to read the full AI-written review.',
              'When next week\'s summary generates, this week\'s banner is automatically replaced.',
              'Change the summary day in Settings → Weekly Summary Day.',
              'If no detections were made that week, no summary is generated.',
            ],
            extras: const [
              Padding(
                padding: EdgeInsets.only(top: 8, bottom: 2),
                child: Divider(color: Color(0xFF334155), height: 1),
              ),
              Padding(
                padding: EdgeInsets.only(top: 12, bottom: 10),
                child: Text(
                  'WHAT THE BANNER COLOR MEANS',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              _BadgeLegendRow(
                color: Color(0xFFF97316),
                badge: 'SAMPLE · TAP TO PREVIEW',
                description:
                    'No real summary yet. Example data so you know what to expect — replaced the moment your first real summary generates.',
              ),
              _BadgeLegendRow(
                color: Color(0xFF22C55E),
                badge: 'NEW THIS WEEK',
                description:
                    'Freshly generated (within 2 days). Your latest weekly results are ready to review.',
              ),
              _BadgeLegendRow(
                color: Color(0xFF3B82F6),
                badge: 'WEEKLY SUMMARY READY',
                description:
                    'This week\'s summary, generated 3–7 days ago and still the current week.',
              ),
              _BadgeLegendRow(
                color: Color(0xFF64748B),
                badge: 'PREVIOUS WEEK',
                description:
                    'An older summary — the current week\'s summary has not generated yet.',
              ),
            ],
          ),
          const _TutorialSection(
            icon: Icons.auto_awesome_outlined,
            title: 'AI Hatchery Assistant — Ask Anything',
            bullets: [
              'Chat directly with an AI that knows your hatchery\'s actual data — your reports, fertility rates, detection history.',
              'Ask natural questions: "Why did fertility drop on Tuesday?" or "Which batch had the best results this week?"',
              'Get expert poultry farming advice tailored to your specific situation, not generic answers.',
              'Ask about incubation conditions, temperature, humidity, flock health — all in plain language.',
              'Available 24/7 — no need to wait for a consultant or flip through manuals.',
            ],
          ),
          const _TutorialSection(
            icon: Icons.tune_outlined,
            title: 'Settings',
            bullets: [
              'Trend Window: choose 7, 14, or 30 days of history shown on the chart.',
              'Weekly Summary Day: pick which day of the week triggers your summary.',
              'Daily Analysis Time: set the time (PKT) when trends and recommendations are generated.',
              'Analysis runs automatically when you open the app after the scheduled time.',
              'A server backup also runs in case the app is not opened that day.',
            ],
          ),
        ],
      ),
    );
  }
}

class _TutorialSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> bullets;
  final List<Widget> extras;

  const _TutorialSection({
    required this.icon,
    required this.title,
    required this.bullets,
    this.extras = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF3B82F6), size: 18),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...bullets.map((b) => _Bullet(text: b)),
                ...extras,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeLegendRow extends StatelessWidget {
  final Color color;
  final String badge;
  final String description;

  const _BadgeLegendRow({
    required this.color,
    required this.badge,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(
              badge,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            description,
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;

  const _Bullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: CircleAvatar(
              radius: 3,
              backgroundColor: Color(0xFF3B82F6),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
