import 'package:flutter/material.dart';

enum AgentSeverity { critical, high, moderate, low, healthy }

AgentSeverity _severityFromString(String? raw) {
  switch (raw) {
    case 'critical':
      return AgentSeverity.critical;
    case 'high':
      return AgentSeverity.high;
    case 'low':
      return AgentSeverity.low;
    case 'healthy':
      return AgentSeverity.healthy;
    case 'moderate':
    default:
      return AgentSeverity.moderate;
  }
}

extension AgentSeverityX on AgentSeverity {
  String get label {
    switch (this) {
      case AgentSeverity.critical:
        return 'Critical';
      case AgentSeverity.high:
        return 'High';
      case AgentSeverity.moderate:
        return 'Moderate';
      case AgentSeverity.low:
        return 'Low';
      case AgentSeverity.healthy:
        return 'Healthy';
    }
  }

  Color get color {
    switch (this) {
      case AgentSeverity.critical:
        return const Color(0xFFD32F2F); // red 700
      case AgentSeverity.high:
        return const Color(0xFFF57C00); // orange 700
      case AgentSeverity.moderate:
        return const Color(0xFFFBC02D); // yellow 700
      case AgentSeverity.low:
        return const Color(0xFF7CB342); // light green 600
      case AgentSeverity.healthy:
        return const Color(0xFF388E3C); // green 700
    }
  }

  IconData get icon {
    switch (this) {
      case AgentSeverity.critical:
      case AgentSeverity.high:
        return Icons.warning_amber_rounded;
      case AgentSeverity.moderate:
        return Icons.info_outline;
      case AgentSeverity.low:
      case AgentSeverity.healthy:
        return Icons.check_circle_outline;
    }
  }
}

class AgentRecommendation {
  final String title;
  final String body;
  final int priority;

  const AgentRecommendation({
    required this.title,
    required this.body,
    required this.priority,
  });

  factory AgentRecommendation.fromJson(Map<String, dynamic> json) {
    return AgentRecommendation(
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      priority: (json['priority'] as num?)?.toInt() ?? 99,
    );
  }

  bool get isUrgent => priority == 1;
}

class AgentToolCall {
  final String name;
  final Map<String, dynamic> args;
  final int iteration;

  const AgentToolCall({required this.name, required this.args, required this.iteration});

  factory AgentToolCall.fromJson(Map<String, dynamic> json) {
    return AgentToolCall(
      name: json['name'] as String? ?? 'unknown',
      args: (json['args'] as Map<String, dynamic>? ?? const {}),
      iteration: (json['iteration'] as num?)?.toInt() ?? 0,
    );
  }
}

class AgentAnalysisModel {
  final String id;
  final String userId;
  final String pktDate;
  final DateTime generatedAt;
  final String diagnosis;
  final AgentSeverity severity;
  final List<String> evidence;
  final String trendNarrative;
  final List<AgentRecommendation> recommendations;
  final List<AgentToolCall> toolsCalled;
  final int iterations;
  final int elapsedMs;

  const AgentAnalysisModel({
    required this.id,
    required this.userId,
    required this.pktDate,
    required this.generatedAt,
    required this.diagnosis,
    required this.severity,
    required this.evidence,
    required this.trendNarrative,
    required this.recommendations,
    required this.toolsCalled,
    required this.iterations,
    required this.elapsedMs,
  });

  factory AgentAnalysisModel.fromJson(Map<String, dynamic> json) {
    final evidenceRaw = json['evidence'] as List<dynamic>? ?? const [];
    final recsRaw = json['recommendations'] as List<dynamic>? ?? const [];
    final toolsRaw = json['toolsCalled'] as List<dynamic>? ?? const [];

    return AgentAnalysisModel(
      id: json['_id']?.toString() ?? '',
      userId: json['userId'] as String? ?? '',
      pktDate: json['pktDate'] as String? ?? '',
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      diagnosis: json['diagnosis'] as String? ?? '',
      severity: _severityFromString(json['severity'] as String?),
      evidence: evidenceRaw.map((e) => e?.toString() ?? '').toList(),
      trendNarrative: json['trendNarrative'] as String? ?? '',
      recommendations: recsRaw
          .map((r) => AgentRecommendation.fromJson(r as Map<String, dynamic>))
          .toList(),
      toolsCalled: toolsRaw
          .map((t) => AgentToolCall.fromJson(t as Map<String, dynamic>))
          .toList(),
      iterations: (json['iterations'] as num?)?.toInt() ?? 0,
      elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
    );
  }

  List<AgentRecommendation> get sortedRecommendations {
    final sorted = List<AgentRecommendation>.from(recommendations);
    sorted.sort((a, b) => a.priority.compareTo(b.priority));
    return sorted;
  }
}
