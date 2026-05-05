import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class UserSettingsService {
  static const String _baseUrl = 'http://192.168.0.44:3000';

  Future<Map<String, String>> _headers() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      return {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
    } catch (e) {
      debugPrint('[USER_SETTINGS] Failed to get auth token: $e');
      return {'Content-Type': 'application/json'};
    }
  }

  /// Returns the user's configured analysis time from the backend.
  /// Defaults to 21:00 PKT if not set.
  Future<({int hour, int minute})> getAnalysisTime() async {
    debugPrint('[USER_SETTINGS] getAnalysisTime');
    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$_baseUrl/user-settings'), headers: headers)
          .timeout(const Duration(seconds: 10));

      debugPrint('[USER_SETTINGS] GET /user-settings → status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (
          hour: (data['analysisHour'] as num?)?.toInt() ?? 21,
          minute: (data['analysisMinute'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (e) {
      debugPrint('[USER_SETTINGS] getAnalysisTime error: $e');
    }
    return (hour: 21, minute: 0);
  }

  /// Saves the user's analysis time to the backend.
  Future<bool> setAnalysisTime(int hour, int minute) async {
    debugPrint('[USER_SETTINGS] setAnalysisTime — $hour:${minute.toString().padLeft(2, '0')}');
    try {
      final headers = await _headers();
      final response = await http
          .post(
            Uri.parse('$_baseUrl/user-settings'),
            headers: headers,
            body: jsonEncode({'analysisHour': hour, 'analysisMinute': minute}),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('[USER_SETTINGS] POST /user-settings → status: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[USER_SETTINGS] setAnalysisTime error: $e');
      return false;
    }
  }
}
