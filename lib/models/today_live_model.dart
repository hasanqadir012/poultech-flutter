class TodayLiveModel {
  final bool hasData;
  final int detectionCount;
  final double averageFertilityRate;
  final int totalEggs;
  final int fertileEggs;
  final int infertileEggs;

  const TodayLiveModel({
    required this.hasData,
    required this.detectionCount,
    required this.averageFertilityRate,
    required this.totalEggs,
    required this.fertileEggs,
    required this.infertileEggs,
  });

  factory TodayLiveModel.fromJson(Map<String, dynamic> json) {
    return TodayLiveModel(
      hasData: json['hasData'] as bool? ?? false,
      detectionCount: (json['detectionCount'] as num?)?.toInt() ?? 0,
      averageFertilityRate: (json['averageFertilityRate'] as num?)?.toDouble() ?? 0.0,
      totalEggs: (json['totalEggs'] as num?)?.toInt() ?? 0,
      fertileEggs: (json['fertileEggs'] as num?)?.toInt() ?? 0,
      infertileEggs: (json['infertileEggs'] as num?)?.toInt() ?? 0,
    );
  }

  String get averagePercent =>
      '${(averageFertilityRate * 100).toStringAsFixed(1)}%';
}
