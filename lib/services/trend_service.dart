import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../models/daily_stat_model.dart';
import '../models/today_live_model.dart';

/// Lean trend service — only the chart-data endpoints remain.
/// The legacy /trends/* endpoints (latest trend doc, history, run-daily-analysis,
/// force-regenerate) are gone — diagnosis + recommendations now come from
/// [AgentAnalysisService].
class TrendService {
  static const String _baseUrl = AppConfig.backendBaseUrl;

  Future<Map<String, String>> _headers() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      return {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
    } catch (e) {
      debugPrint('[TREND] Failed to get auth token: $e');
      return {'Content-Type': 'application/json'};
    }
  }

  /// Returns today's live running average without triggering analysis.
  Future<TodayLiveModel?> getTodayLive() async {
    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$_baseUrl/trends/today'), headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return TodayLiveModel.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('[TREND] getTodayLive error: $e');
      return null;
    }
  }

  /// Returns daily aggregated stats for the chart (one entry per day, oldest first).
  Future<List<DailyStatModel>> getDailyStats({int days = 14}) async {
    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$_baseUrl/daily-stats?days=$days'), headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        return data
            .map((j) => DailyStatModel.fromJson(j as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[TREND] getDailyStats error: $e');
      return [];
    }
  }
}
