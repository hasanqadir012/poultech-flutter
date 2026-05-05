import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import '../models/summary_model.dart';

class SummaryService {
  static const String _baseUrl = AppConfig.backendBaseUrl;

  Future<Map<String, String>> _headers() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      return {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
    } catch (e) {
      debugPrint('[SUMMARY] Failed to get auth token: $e');
      return {'Content-Type': 'application/json'};
    }
  }

  /// Checks if today is the configured summary day. If so, fires a
  /// non-blocking POST to generate (or return existing) weekly summary.
  /// Should be called from dashboard initState as fire-and-forget.
  Future<void> checkAndGenerateWeeklySummary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final summaryDay = prefs.getInt('summary_day_of_week') ?? 1; // 1 = Monday

      if (DateTime.now().weekday != summaryDay) return;

      final now = DateTime.now();
      // Summarized period = the 7 days that just ended (yesterday back to 8 days ago)
      final todayMidnight = DateTime(now.year, now.month, now.day);
      final weekStart = todayMidnight.subtract(const Duration(days: 7));
      final weekEnd = DateTime(
        todayMidnight.year,
        todayMidnight.month,
        todayMidnight.day - 1,
        23,
        59,
        59,
      );

      debugPrint(
        '[SUMMARY] Summary day matched — generating for '
        '${weekStart.toIso8601String()} to ${weekEnd.toIso8601String()}',
      );

      final headers = await _headers();
      final response = await http
          .post(
            Uri.parse('$_baseUrl/summaries/generate'),
            headers: headers,
            body: jsonEncode({
              'weekStart': weekStart.toIso8601String(),
              'weekEnd': weekEnd.toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('[SUMMARY] POST /generate → status: ${response.statusCode}');
    } catch (e) {
      debugPrint('[SUMMARY] checkAndGenerateWeeklySummary error: $e');
    }
  }

  Future<SummaryModel?> getLatestSummary() async {
    debugPrint('[SUMMARY] getLatestSummary');
    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$_baseUrl/summaries/latest'), headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('[SUMMARY] GET /latest → status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data == null) return null;
        return SummaryModel.fromJson(data as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[SUMMARY] getLatestSummary error: $e');
      return null;
    }
  }

  Future<List<SummaryModel>> getAllSummaries() async {
    debugPrint('[SUMMARY] getAllSummaries');
    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$_baseUrl/summaries'), headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('[SUMMARY] GET / → status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        return data
            .map((j) => SummaryModel.fromJson(j as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[SUMMARY] getAllSummaries error: $e');
      return [];
    }
  }

  Future<bool> markRead(String summaryId) async {
    debugPrint('[SUMMARY] markRead — id: $summaryId');
    try {
      final headers = await _headers();
      final response = await http
          .patch(
            Uri.parse('$_baseUrl/summaries/$summaryId/read'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('[SUMMARY] PATCH /read → status: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[SUMMARY] markRead error: $e');
      return false;
    }
  }
}
