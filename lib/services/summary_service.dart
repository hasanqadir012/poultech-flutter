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

  /// Fires a non-blocking POST to generate (or return existing) weekly summary
  /// for the most recently completed summary period based on the user's chosen day.
  /// Catches up automatically if the app was not opened on the configured day.
  /// Should be called from dashboard initState as fire-and-forget.
  Future<void> checkAndGenerateWeeklySummary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final summaryDay = prefs.getInt('summary_day_of_week') ?? 1; // 1 = Monday

      final now = DateTime.now();
      final todayMidnight = DateTime(now.year, now.month, now.day);

      // Find the most recent past occurrence of the user's chosen summary day.
      // daysSince = 0 when today IS the summary day; otherwise days elapsed since last one.
      final daysSince = (now.weekday - summaryDay + 7) % 7;

      // If today is the summary day (daysSince == 0) use today; otherwise use last occurrence.
      // Skip if the summary day has never occurred yet (first day of the week cycle hasn't passed).
      final lastSummaryDay = daysSince == 0 && now.weekday == summaryDay
          ? todayMidnight
          : todayMidnight.subtract(Duration(days: daysSince == 0 ? 7 : daysSince));

      // Summarized period = the 7 days ending the day before the last summary day.
      final weekStart = lastSummaryDay.subtract(const Duration(days: 7));
      final weekEnd = DateTime(
        lastSummaryDay.year,
        lastSummaryDay.month,
        lastSummaryDay.day - 1,
        23,
        59,
        59,
      );

      debugPrint(
        '[SUMMARY] Generating for '
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

  /// Force-regenerate the most recent summary using its existing weekStart/weekEnd.
  /// Returns the new SummaryModel on success, or null if no prior summary exists
  /// or regeneration failed. Does NOT shift the regular weekly schedule.
  Future<SummaryModel?> forceRegenerate() async {
    debugPrint('[SUMMARY] forceRegenerate');
    try {
      final headers = await _headers();
      final response = await http
          .post(Uri.parse('$_baseUrl/summaries/force-regenerate'), headers: headers)
          .timeout(const Duration(seconds: 45));

      debugPrint('[SUMMARY] POST /force-regenerate → status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // Endpoint returns either the new summary doc directly, or
        // { ran: true, regenerated: false, reason: ... } when no reports remain.
        if (data['regenerated'] == false) return null;
        return SummaryModel.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint('[SUMMARY] forceRegenerate error: $e');
      return null;
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
