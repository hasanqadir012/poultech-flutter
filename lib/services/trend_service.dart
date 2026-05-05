import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/daily_stat_model.dart';
import '../models/today_live_model.dart';
import '../models/trend_model.dart';

class TrendService {
  static const String _baseUrl = 'http://192.168.0.44:3000';

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

  Future<TrendModel?> getLatestTrend({int windowDays = 14}) async {
    debugPrint('[TREND] getLatestTrend — windowDays: $windowDays');
    try {
      final headers = await _headers();
      final response = await http
          .get(
            Uri.parse('$_baseUrl/trends/latest?days=$windowDays'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('[TREND] GET /trends/latest → status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data == null) return null;
        return TrendModel.fromJson(data as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[TREND] getLatestTrend error: $e');
      return null;
    }
  }

  Future<List<TrendModel>> getTrendHistory() async {
    debugPrint('[TREND] getTrendHistory');
    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$_baseUrl/trends'), headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('[TREND] GET /trends → status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        debugPrint('[TREND] getTrendHistory — ${data.length} records');
        return data
            .map((j) => TrendModel.fromJson(j as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[TREND] getTrendHistory error: $e');
      return [];
    }
  }

  /// Returns today's live running average without triggering analysis.
  Future<TodayLiveModel?> getTodayLive() async {
    debugPrint('[TREND] getTodayLive');
    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$_baseUrl/trends/today'), headers: headers)
          .timeout(const Duration(seconds: 10));

      debugPrint('[TREND] GET /trends/today → status: ${response.statusCode}');

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

  /// Fires POST /trends/run-daily-analysis silently.
  /// Backend returns { ran: false } if too early or already ran — no action needed.
  Future<void> triggerDailyAnalysis() async {
    debugPrint('[TREND] triggerDailyAnalysis');
    try {
      final headers = await _headers();
      final response = await http
          .post(Uri.parse('$_baseUrl/trends/run-daily-analysis'), headers: headers)
          .timeout(const Duration(seconds: 30));

      debugPrint('[TREND] POST /run-daily-analysis → status: ${response.statusCode}, body: ${response.body}');
    } catch (e) {
      debugPrint('[TREND] triggerDailyAnalysis error: $e');
    }
  }

  /// Returns daily aggregated stats for the chart (one entry per day, oldest first).
  Future<List<DailyStatModel>> getDailyStats({int days = 14}) async {
    debugPrint('[TREND] getDailyStats — days: $days');
    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$_baseUrl/daily-stats?days=$days'), headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('[TREND] GET /daily-stats → status: ${response.statusCode}');

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
