class SummaryModel {
  final String id;
  final String userId;
  final DateTime weekStart;
  final DateTime weekEnd;
  final DateTime generatedAt;
  final int reportCount;
  final int totalEggsAnalyzed;
  final int totalFertileEggs;
  final int totalInfertileEggs;
  final double averageFertilityRate;
  final double highestFertilityRate;
  final double lowestFertilityRate;
  final String? bestBatchLabel;
  final String? worstBatchLabel;
  final int batchesActive;
  final String agentSummary;
  final bool isRead;

  const SummaryModel({
    required this.id,
    required this.userId,
    required this.weekStart,
    required this.weekEnd,
    required this.generatedAt,
    required this.reportCount,
    required this.totalEggsAnalyzed,
    required this.totalFertileEggs,
    required this.totalInfertileEggs,
    required this.averageFertilityRate,
    required this.highestFertilityRate,
    required this.lowestFertilityRate,
    this.bestBatchLabel,
    this.worstBatchLabel,
    required this.batchesActive,
    required this.agentSummary,
    required this.isRead,
  });

  factory SummaryModel.fromJson(Map<String, dynamic> json) {
    return SummaryModel(
      id: json['_id']?.toString() ?? '',
      userId: json['userId'] as String? ?? '',
      weekStart: DateTime.parse(json['weekStart'] as String),
      weekEnd: DateTime.parse(json['weekEnd'] as String),
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      reportCount: (json['reportCount'] as num).toInt(),
      totalEggsAnalyzed: (json['totalEggsAnalyzed'] as num).toInt(),
      totalFertileEggs: (json['totalFertileEggs'] as num).toInt(),
      totalInfertileEggs: (json['totalInfertileEggs'] as num).toInt(),
      averageFertilityRate: (json['averageFertilityRate'] as num).toDouble(),
      highestFertilityRate: (json['highestFertilityRate'] as num).toDouble(),
      lowestFertilityRate: (json['lowestFertilityRate'] as num).toDouble(),
      bestBatchLabel: json['bestBatchLabel'] as String?,
      worstBatchLabel: json['worstBatchLabel'] as String?,
      batchesActive: (json['batchesActive'] as num).toInt(),
      agentSummary: json['agentSummary'] as String? ?? '',
      isRead: json['isRead'] as bool? ?? false,
    );
  }

  String get averagePercent =>
      '${(averageFertilityRate * 100).toStringAsFixed(1)}%';

  String get formattedWeekRange {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final start = '${months[weekStart.month - 1]} ${weekStart.day}';
    final end = '${months[weekEnd.month - 1]} ${weekEnd.day}';
    return '$start – $end';
  }

  // True if this summary covers the current or most recent period (within last 7 days)
  bool get isCurrentPeriod {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    return weekStart.isAfter(sevenDaysAgo);
  }
}
