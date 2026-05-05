import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../app_config.dart';
import '../models/report_model.dart';
import '../models/chat_session_model.dart';
import '../models/chat_message_model.dart';

class SaveResult {
  final String? reportId;
  final String? errorMessage;
  final bool isSuccess;

  SaveResult._({this.reportId, this.errorMessage, required this.isSuccess});

  factory SaveResult.success(String id) =>
      SaveResult._(reportId: id, isSuccess: true);

  factory SaveResult.failure(String message) =>
      SaveResult._(errorMessage: message, isSuccess: false);
}

class DatabaseService {
  // Replace with your Railway deployment URL after backend is deployed.
  // Example: 'https://poultech-api-production.up.railway.app'
  // Local dev: use your machine's LAN IP so the physical device can reach it.
  // After Railway deploy, replace with your Railway URL (https://...).
  static const String _baseUrl = AppConfig.backendBaseUrl;

  Future<String?> _getAuthToken() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      debugPrint('[DB] Auth token fetched — length: ${token?.length ?? 0}');
      return token;
    } catch (e) {
      debugPrint('[DB] Failed to get auth token: $e');
      return null;
    }
  }

  Future<Map<String, String>> _headers() async {
    final token = await _getAuthToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ── Reports ──────────────────────────────────────────────────────────────

  Future<SaveResult> saveReport(ReportModel report) async {
    debugPrint('[DB] saveReport — userId: ${report.userId}, '
        'totalEggs: ${report.totalEggs}, fertileEggs: ${report.fertileEggs}, '
        'fertilityRate: ${report.fertilityRate}');
    try {
      final headers = await _headers();
      final body = jsonEncode(report.toJson());
      debugPrint('[DB] POST $_baseUrl/reports — body keys: ${report.toJson().keys.toList()}');

      final response = await http
          .post(Uri.parse('$_baseUrl/reports'), headers: headers, body: body)
          .timeout(const Duration(seconds: 15));

      debugPrint('[DB] POST /reports → status: ${response.statusCode}');

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final id = data['_id']?.toString() ?? '';
        debugPrint('[DB] Report saved — id: $id');
        return SaveResult.success(id);
      }
      debugPrint('[DB] saveReport failed — body: ${response.body}');
      return SaveResult.failure('Failed to save report. Please try again.');
    } catch (e) {
      debugPrint('[DB] saveReport error: $e');
      return SaveResult.failure('No connection. Check your internet and try again.');
    }
  }

  Future<List<ReportModel>> getReports() async {
    debugPrint('[DB] getReports — fetching user reports');
    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$_baseUrl/reports'), headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('[DB] GET /reports → status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        final reports = data
            .map((json) => ReportModel.fromJson(json as Map<String, dynamic>))
            .toList();
        debugPrint('[DB] getReports — fetched ${reports.length} reports');
        return reports;
      }
      debugPrint('[DB] getReports failed — status: ${response.statusCode}');
      return [];
    } catch (e) {
      debugPrint('[DB] getReports error: $e');
      return [];
    }
  }

  Future<bool> deleteReport(String reportId) async {
    debugPrint('[DB] deleteReport — reportId: $reportId');
    try {
      final headers = await _headers();
      final response = await http
          .delete(Uri.parse('$_baseUrl/reports/$reportId'), headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('[DB] DELETE /reports/$reportId → status: ${response.statusCode}');
      final success = response.statusCode == 200;
      if (!success) debugPrint('[DB] deleteReport failed — body: ${response.body}');
      return success;
    } catch (e) {
      debugPrint('[DB] deleteReport error: $e');
      return false;
    }
  }

  // ── Chat Sessions ─────────────────────────────────────────────────────────

  Future<String?> createChatSession() async {
    debugPrint('[DB] createChatSession');
    try {
      final headers = await _headers();
      final response = await http
          .post(Uri.parse('$_baseUrl/chat/sessions'), headers: headers, body: '{}')
          .timeout(const Duration(seconds: 15));

      debugPrint('[DB] POST /chat/sessions → status: ${response.statusCode}');

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final id = data['_id']?.toString();
        debugPrint('[DB] Chat session created — id: $id');
        return id;
      }
      debugPrint('[DB] createChatSession failed — body: ${response.body}');
      return null;
    } catch (e) {
      debugPrint('[DB] createChatSession error: $e');
      return null;
    }
  }

  Future<bool> appendChatMessage(String sessionId, ChatMessageModel message) async {
    debugPrint('[DB] appendChatMessage — sessionId: $sessionId, '
        'role: ${message.role.name}, contentLength: ${message.content.length}');
    try {
      final headers = await _headers();
      final body = jsonEncode(message.toJson());
      final response = await http
          .post(
            Uri.parse('$_baseUrl/chat/sessions/$sessionId/messages'),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('[DB] POST /chat/sessions/$sessionId/messages → status: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[DB] appendChatMessage error: $e');
      return false;
    }
  }

  Future<List<ChatSessionModel>> getChatSessions({int limit = 30}) async {
    debugPrint('[DB] getChatSessions — limit: $limit');
    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$_baseUrl/chat/sessions?limit=$limit'), headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('[DB] GET /chat/sessions → status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        final sessions = data
            .map((json) => ChatSessionModel.fromJson(json as Map<String, dynamic>))
            .where((s) => s.messages.isNotEmpty)
            .toList();
        debugPrint('[DB] getChatSessions — ${sessions.length} non-empty sessions');
        return sessions;
      }
      return [];
    } catch (e) {
      debugPrint('[DB] getChatSessions error: $e');
      return [];
    }
  }

  Future<ChatSessionModel?> getLatestChatSession() async {
    debugPrint('[DB] getLatestChatSession');
    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$_baseUrl/chat/sessions?limit=1'), headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('[DB] GET /chat/sessions → status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        if (data.isEmpty) {
          debugPrint('[DB] getLatestChatSession — no sessions found');
          return null;
        }
        final session = ChatSessionModel.fromJson(data.first as Map<String, dynamic>);
        debugPrint('[DB] getLatestChatSession — id: ${session.id}, '
            'messages: ${session.messages.length}');
        return session;
      }
      return null;
    } catch (e) {
      debugPrint('[DB] getLatestChatSession error: $e');
      return null;
    }
  }

  Future<bool> deleteChatSession(String sessionId) async {
    debugPrint('[DB] deleteChatSession — sessionId: $sessionId');
    try {
      final headers = await _headers();
      final response = await http
          .delete(Uri.parse('$_baseUrl/chat/sessions/$sessionId'), headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('[DB] DELETE /chat/sessions/$sessionId → status: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[DB] deleteChatSession error: $e');
      return false;
    }
  }
}
