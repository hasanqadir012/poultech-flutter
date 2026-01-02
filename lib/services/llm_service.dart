import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class LLMService {
  static const String _defaultInvokeUrl =
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";

  static String get _invokeUrl =>
      dotenv.env['GEMINI_API_URL']?.trim().isNotEmpty == true
          ? dotenv.env['GEMINI_API_URL']!.trim()
          : _defaultInvokeUrl;

  static String get _apiKey {
    final key = dotenv.env['GEMINI_API_KEY']?.trim();
    if (key == null || key.isEmpty) {
      throw Exception('Missing GEMINI_API_KEY in .env');
    }
    return key;
  }

  static String _encodeImage(File imageFile) {
    final bytes = imageFile.readAsBytesSync();
    return base64Encode(bytes);
  }

  /// Generates a professional fertility analysis report using Gemini
  static Future<String> generateReport(
      File imageFile, Map<String, dynamic> stats) async {
    final imgB64 = _encodeImage(imageFile);

    final total = stats['total'] ?? 0;
    final fertile = stats['fertile'] ?? 0;
    final infertile = stats['infertile'] ?? 0;
    final rate =
        total > 0 ? (fertile / total * 100).toStringAsFixed(1) : "0";

    final reportPrompt = """
You are a Senior Agricultural Quality Control Specialist specializing in Poultry Incubation.

DATA:
- Total Eggs: $total
- Fertile Eggs: $fertile
- Infertile Eggs: $infertile
- Fertility Rate: $rate%

TASK:
Generate a professional Markdown report containing:
1. Executive Summary
2. Statistical Breakdown (Markdown table)
3. Biological Interpretation of a $rate% fertility rate
4. 3 Actionable Recommendations

STYLE:
Scientific, concise, authoritative.
Return ONLY the report text.
""";

    final payload = {
      "contents": [
        {
          "role": "user",
          "parts": [
            {"text": reportPrompt},
            {
              "inline_data": {
                "mime_type": "image/png",
                "data": imgB64
              }
            }
          ]
        }
      ],
      "generationConfig": {
        "maxOutputTokens": 1200,
        "temperature": 0.3
      }
    };

    final response = await http.post(
      Uri.parse("$_invokeUrl?key=$_apiKey"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return jsonResponse["candidates"][0]["content"]["parts"][0]["text"];
    } else {
      throw Exception(
          'Failed to generate report: ${response.statusCode} ${response.body}');
    }
  }

  /// Poultech domain-restricted assistant
  static Future<String> getAssistantResponse(String query) async {
    final assistantPrompt = """
You are the Poultech Knowledge Assistant.
You are an expert in poultry farming, avian embryology, and egg incubation.

Rules:
- Answer in under 3 sentences.
- If unrelated to poultry or eggs, politely redirect.

User Question:
"$query"
""";

    final payload = {
      "contents": [
        {
          "role": "user",
          "parts": [
            {"text": assistantPrompt}
          ]
        }
      ],
      "generationConfig": {
        "maxOutputTokens": 300,
        "temperature": 0.5
      }
    };

    final response = await http.post(
      Uri.parse("$_invokeUrl?key=$_apiKey"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return jsonResponse["candidates"][0]["content"]["parts"][0]["text"];
    } else {
      throw Exception(
          'Assistant error: ${response.statusCode} ${response.body}');
    }
  }
}
