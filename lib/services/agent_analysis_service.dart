import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';
import '../models/agent_analysis_model.dart';

/// Client for the agentic backend (/agent/* routes).
/// Distinct from `agent_service.dart` which serves the knowledge-chat agent.
class AgentAnalysisService {
  static const String _baseUrl = AppConfig.backendBaseUrl;

  Future<Map<String, String>> _headers() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      return {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
    } catch (e) {
      debugPrint('[AGENT_ANALYSIS] Failed to get auth token: $e');
      return {'Content-Type': 'application/json'};
    }
  }

  /// Returns the most recent agent analysis across all days, or null if none yet.
  Future<AgentAnalysisModel?> getLatest() async {
    debugPrint('[AGENT_ANALYSIS] getLatest');
    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$_baseUrl/agent/latest'), headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('[AGENT_ANALYSIS] GET /latest → status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data == null) return null;
        return AgentAnalysisModel.fromJson(data as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[AGENT_ANALYSIS] getLatest error: $e');
      return null;
    }
  }

  /// Returns today's agent analysis (PKT day), or null if not yet generated.
  Future<AgentAnalysisModel?> getToday() async {
    debugPrint('[AGENT_ANALYSIS] getToday');
    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$_baseUrl/agent/today'), headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('[AGENT_ANALYSIS] GET /today → status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data == null) return null;
        return AgentAnalysisModel.fromJson(data as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('[AGENT_ANALYSIS] getToday error: $e');
      return null;
    }
  }

  /// Triggers POST /agent/analyze. Backend runs the agent in background and
  /// returns immediately. Caller should poll getToday() after ~15s.
  /// Returns true if the request was accepted.
  Future<bool> triggerAnalysis() async {
    debugPrint('[AGENT_ANALYSIS] triggerAnalysis');
    try {
      final headers = await _headers();
      final response = await http
          .post(Uri.parse('$_baseUrl/agent/analyze'), headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint(
        '[AGENT_ANALYSIS] POST /analyze → status: ${response.statusCode}, body: ${response.body}',
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[AGENT_ANALYSIS] triggerAnalysis error: $e');
      return false;
    }
  }

  /// Force-regenerate today's agent analysis. Clears the cached doc and reruns.
  /// Returns true on accepted request. New doc is written async (~10–15s).
  Future<bool> forceRegenerate() async {
    debugPrint('[AGENT_ANALYSIS] forceRegenerate');
    try {
      final headers = await _headers();
      final response = await http
          .post(Uri.parse('$_baseUrl/agent/force-regenerate'), headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint(
        '[AGENT_ANALYSIS] POST /force-regenerate → status: ${response.statusCode}, body: ${response.body}',
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[AGENT_ANALYSIS] forceRegenerate error: $e');
      return false;
    }
  }
}
