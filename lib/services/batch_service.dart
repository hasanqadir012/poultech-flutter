import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../models/batch_model.dart';

class BatchResult {
  final BatchModel? batch;
  final String? errorMessage;
  final bool isSuccess;

  BatchResult._({this.batch, this.errorMessage, required this.isSuccess});

  factory BatchResult.success(BatchModel batch) =>
      BatchResult._(batch: batch, isSuccess: true);

  factory BatchResult.failure(String message) =>
      BatchResult._(errorMessage: message, isSuccess: false);
}

class BatchService {
  static const String _baseUrl = 'http://192.168.0.44:3000';

  Future<String?> _getAuthToken() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      return token;
    } catch (e) {
      debugPrint('[BATCH] Failed to get auth token: $e');
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

  Future<BatchResult> createBatch(String name, String? notes) async {
    debugPrint('[BATCH] createBatch — name: "$name"');
    try {
      final headers = await _headers();
      final body = jsonEncode({'name': name, 'notes': notes});
      final response = await http
          .post(Uri.parse('$_baseUrl/batches'), headers: headers, body: body)
          .timeout(const Duration(seconds: 15));

      debugPrint('[BATCH] POST /batches → status: ${response.statusCode}');

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final batch = BatchModel.fromJson(data);
        debugPrint('[BATCH] Created batch — id: ${batch.id}');
        return BatchResult.success(batch);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final message = data['error'] as String? ?? 'Failed to create batch.';
      debugPrint('[BATCH] createBatch failed — body: ${response.body}');
      return BatchResult.failure(message);
    } catch (e) {
      debugPrint('[BATCH] createBatch error: $e');
      return BatchResult.failure('No connection. Check your internet and try again.');
    }
  }

  Future<BatchModel?> getActiveBatch() async {
    debugPrint('[BATCH] getActiveBatch');
    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$_baseUrl/batches/active'), headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('[BATCH] GET /batches/active → status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['active'] == false) {
          debugPrint('[BATCH] No active batch');
          return null;
        }
        final batch = BatchModel.fromJson(data);
        debugPrint('[BATCH] Active batch — id: ${batch.id}, name: "${batch.name}"');
        return batch;
      }
      return null;
    } catch (e) {
      debugPrint('[BATCH] getActiveBatch error: $e');
      return null;
    }
  }

  Future<List<BatchModel>> getAllBatches() async {
    debugPrint('[BATCH] getAllBatches');
    try {
      final headers = await _headers();
      final response = await http
          .get(Uri.parse('$_baseUrl/batches'), headers: headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('[BATCH] GET /batches → status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        final batches = data
            .map((json) => BatchModel.fromJson(json as Map<String, dynamic>))
            .toList();
        debugPrint('[BATCH] getAllBatches — ${batches.length} batches');
        return batches;
      }
      return [];
    } catch (e) {
      debugPrint('[BATCH] getAllBatches error: $e');
      return [];
    }
  }

  Future<bool> closeBatch(String batchId) async {
    debugPrint('[BATCH] closeBatch — batchId: $batchId');
    try {
      final headers = await _headers();
      final response = await http
          .patch(
            Uri.parse('$_baseUrl/batches/$batchId/close'),
            headers: headers,
            body: '{}',
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('[BATCH] PATCH /batches/$batchId/close → status: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[BATCH] closeBatch error: $e');
      return false;
    }
  }
}
