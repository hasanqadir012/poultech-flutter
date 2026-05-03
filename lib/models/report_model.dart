enum FertilityStatus { good, moderate, poor }

class ReportModel {
  final String? id;
  final String userId;
  final DateTime createdAt;
  final String? batchLabel;
  final int totalEggs;
  final int fertileEggs;
  final int infertileEggs;
  final double fertilityRate;
  final String reportText;
  final String? imagePath;

  ReportModel({
    this.id,
    required this.userId,
    required this.createdAt,
    this.batchLabel,
    required this.totalEggs,
    required this.fertileEggs,
    required this.infertileEggs,
    required this.fertilityRate,
    required this.reportText,
    this.imagePath,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'createdAt': createdAt.toIso8601String(),
        'batchLabel': batchLabel,
        'totalEggs': totalEggs,
        'fertileEggs': fertileEggs,
        'infertileEggs': infertileEggs,
        'fertilityRate': fertilityRate,
        'reportText': reportText,
        'imagePath': imagePath,
      };

  factory ReportModel.fromJson(Map<String, dynamic> json) {
    return ReportModel(
      id: json['_id']?.toString(),
      userId: json['userId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      batchLabel: json['batchLabel'] as String?,
      totalEggs: (json['totalEggs'] as num).toInt(),
      fertileEggs: (json['fertileEggs'] as num).toInt(),
      infertileEggs: (json['infertileEggs'] as num).toInt(),
      fertilityRate: (json['fertilityRate'] as num).toDouble(),
      reportText: json['reportText'] as String,
      imagePath: json['imagePath'] as String?,
    );
  }

  String get fertilityPercent => '${(fertilityRate * 100).toStringAsFixed(1)}%';

  String get formattedDate {
    final d = createdAt;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  FertilityStatus get status {
    if (fertilityRate >= 0.75) return FertilityStatus.good;
    if (fertilityRate >= 0.50) return FertilityStatus.moderate;
    return FertilityStatus.poor;
  }
}
