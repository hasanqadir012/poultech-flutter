import 'package:flutter/material.dart';

class RecommendationItem {
  final int priority;
  final String category;
  final String title;
  final String action;
  final String reason;

  const RecommendationItem({
    required this.priority,
    required this.category,
    required this.title,
    required this.action,
    required this.reason,
  });

  factory RecommendationItem.fromJson(Map<String, dynamic> json) {
    return RecommendationItem(
      priority: (json['priority'] as num).toInt(),
      category: json['category'] as String? ?? 'general',
      title: json['title'] as String? ?? '',
      action: json['action'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
    );
  }

  bool get isUrgent => priority == 1;

  IconData get categoryIcon {
    switch (category) {
      case 'rooster_health':
        return Icons.medical_services_outlined;
      case 'flock_management':
        return Icons.groups_outlined;
      case 'incubator':
        return Icons.thermostat_outlined;
      case 'egg_handling':
        return Icons.egg_outlined;
      case 'monitoring':
        return Icons.monitor_heart_outlined;
      default:
        return Icons.lightbulb_outline;
    }
  }
}

class RecommendationsModel {
  final String id;
  final String userId;
  final String? trendId;
  final DateTime generatedAt;
  final bool isRead;
  final List<RecommendationItem> items;

  const RecommendationsModel({
    required this.id,
    required this.userId,
    this.trendId,
    required this.generatedAt,
    required this.isRead,
    required this.items,
  });

  factory RecommendationsModel.fromJson(Map<String, dynamic> json) {
    final rawItems = json['recommendations'] as List<dynamic>? ?? [];
    return RecommendationsModel(
      id: json['_id']?.toString() ?? '',
      userId: json['userId'] as String? ?? '',
      trendId: json['trendId'] as String?,
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      isRead: json['isRead'] as bool? ?? false,
      items: rawItems
          .map((j) => RecommendationItem.fromJson(j as Map<String, dynamic>))
          .toList(),
    );
  }

  List<RecommendationItem> get sortedByPriority {
    final sorted = List<RecommendationItem>.from(items);
    sorted.sort((a, b) => a.priority.compareTo(b.priority));
    return sorted;
  }
}
