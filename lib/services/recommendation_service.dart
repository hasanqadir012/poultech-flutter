import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/recommendation_model.dart';

class RecommendationService {
  static const String _baseUrl = 'http://192.168.0.44:3000';

  Future<Map<String, String>> _headers() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      return {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
    } catch (e) {
      debugPrint('[RECOMMEND] Failed to get auth token: $e');
      return {'Content-Type': 'application/json'};
    }
  }

  Future<RecommendationsModel?> getLatestRecommendations() async {
    debugPrint('[RECOMMEND] getLatestRecommendations');
    try {
      final headers = await _headers();
      final response = await http
          .get(
            Uri.parse('$_baseUrl/recommendations/latest'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('[RECOMMEND] GET /latest → status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data == null) return null;
        return RecommendationsModel.fromJson(data as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[RECOMMEND] getLatestRecommendations error: $e');
      return null;
    }
  }

  Future<bool> markRead(String recommendationId) async {
    debugPrint('[RECOMMEND] markRead — id: $recommendationId');
    try {
      final headers = await _headers();
      final response = await http
          .patch(
            Uri.parse('$_baseUrl/recommendations/$recommendationId/read'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('[RECOMMEND] PATCH /read → status: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[RECOMMEND] markRead error: $e');
      return false;
    }
  }
}
