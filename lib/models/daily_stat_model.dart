class DailyStatModel {
  final String date; // "YYYY-MM-DD" in PKT
  final int detectionCount;
  final int totalEggs;
  final int fertileEggs;
  final int infertileEggs;
  final double averageFertilityRate;
  final double highestRate;
  final double lowestRate;
  final DateTime generatedAt;

  const DailyStatModel({
    required this.date,
    required this.detectionCount,
    required this.totalEggs,
    required this.fertileEggs,
    required this.infertileEggs,
    required this.averageFertilityRate,
    required this.highestRate,
    required this.lowestRate,
    required this.generatedAt,
  });

  factory DailyStatModel.fromJson(Map<String, dynamic> json) {
    return DailyStatModel(
      date: json['date'] as String? ?? '',
      detectionCount: (json['detectionCount'] as num?)?.toInt() ?? 0,
      totalEggs: (json['totalEggs'] as num?)?.toInt() ?? 0,
      fertileEggs: (json['fertileEggs'] as num?)?.toInt() ?? 0,
      infertileEggs: (json['infertileEggs'] as num?)?.toInt() ?? 0,
      averageFertilityRate: (json['averageFertilityRate'] as num?)?.toDouble() ?? 0.0,
      highestRate: (json['highestRate'] as num?)?.toDouble() ?? 0.0,
      lowestRate: (json['lowestRate'] as num?)?.toDouble() ?? 0.0,
      generatedAt: json['generatedAt'] != null
          ? DateTime.parse(json['generatedAt'] as String)
          : DateTime.now(),
    );
  }

  String get averagePercent =>
      '${(averageFertilityRate * 100).toStringAsFixed(1)}%';

  // e.g. "May 4" from "2026-05-04"
  String get dateLabel {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final parts = date.split('-');
    if (parts.length < 3) return date;
    final month = int.tryParse(parts[1]) ?? 1;
    final day = int.tryParse(parts[2]) ?? 1;
    return '${months[month - 1]} $day';
  }
}
