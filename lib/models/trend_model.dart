import 'package:flutter/material.dart';

class TrendModel {
  final String? id;
  final String userId;
  final DateTime generatedAt;
  final int windowDays;
  final int reportCount;
  final double averageFertilityRate;
  final String trend; // 'improving' | 'declining' | 'stable'
  final String trendStrength; // 'strong' | 'moderate' | 'slight' | 'insufficient_data'
  final double highestRate;
  final double lowestRate;
  final double firstRate;
  final double lastRate;
  final String agentSummary;

  const TrendModel({
    this.id,
    required this.userId,
    required this.generatedAt,
    required this.windowDays,
    required this.reportCount,
    required this.averageFertilityRate,
    required this.trend,
    required this.trendStrength,
    required this.highestRate,
    required this.lowestRate,
    required this.firstRate,
    required this.lastRate,
    required this.agentSummary,
  });

  factory TrendModel.fromJson(Map<String, dynamic> json) {
    return TrendModel(
      id: json['_id']?.toString(),
      userId: json['userId'] as String,
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      windowDays: (json['windowDays'] as num).toInt(),
      reportCount: (json['reportCount'] as num).toInt(),
      averageFertilityRate: (json['averageFertilityRate'] as num).toDouble(),
      trend: json['trend'] as String,
      trendStrength: json['trendStrength'] as String,
      highestRate: (json['highestRate'] as num).toDouble(),
      lowestRate: (json['lowestRate'] as num).toDouble(),
      firstRate: (json['firstRate'] as num).toDouble(),
      lastRate: (json['lastRate'] as num).toDouble(),
      agentSummary: json['agentSummary'] as String,
    );
  }

  bool get hasInsufficientData => trendStrength == 'insufficient_data';

  String get averagePercent =>
      '${(averageFertilityRate * 100).toStringAsFixed(1)}%';

  Color get trendColor {
    if (hasInsufficientData) return const Color(0xFF64748B);
    switch (trend) {
      case 'improving':
        return const Color(0xFF22C55E);
      case 'declining':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF3B82F6);
    }
  }

  IconData get trendIcon {
    if (hasInsufficientData) return Icons.show_chart;
    switch (trend) {
      case 'improving':
        return Icons.trending_up;
      case 'declining':
        return Icons.trending_down;
      default:
        return Icons.trending_flat;
    }
  }

  String get trendLabel {
    if (hasInsufficientData) return 'Insufficient Data';
    final prefix = trendStrength == 'slight' ? '' : '${_cap(trendStrength)} ';
    switch (trend) {
      case 'improving':
        return '${prefix}Improving ↗';
      case 'declining':
        return '${prefix}Decline ↘';
      default:
        return 'Stable →';
    }
  }

  String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
