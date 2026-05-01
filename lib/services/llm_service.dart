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

  /// Posts payload to Gemini and returns the response text.
  /// Throws [_TruncatedResponseException] if the response is truncated (MAX_TOKENS finish reason).
  static Future<String> _post(Map<String, dynamic> payload) async {
    final response = await http
        .post(
          Uri.parse("$_invokeUrl?key=$_apiKey"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception(
        'Gemini API error: ${response.statusCode} ${response.body}',
      );
    }

    final jsonResponse = jsonDecode(response.body);
    final candidate = jsonResponse["candidates"][0];
    final finishReason = candidate["finishReason"] ?? "STOP";
    final text = candidate["content"]["parts"][0]["text"] as String;

    // If the model ran out of tokens, the response is incomplete
    if (finishReason == "MAX_TOKENS") {
      throw _TruncatedResponseException(text);
    }

    return text;
  }

  /// Generates a professional fertility analysis report using Gemini.
  /// Automatically retries with a condensed prompt if the first attempt is truncated.
  static Future<String> generateReport(
    File imageFile,
    Map<String, dynamic> stats,
  ) async {
    final imgB64 = _encodeImage(imageFile);

    final total = stats['total'] ?? 0;
    final fertile = stats['fertile'] ?? 0;
    final infertile = stats['infertile'] ?? 0;
    final rate = total > 0 ? (fertile / total * 100).toStringAsFixed(1) : "0";

    final reportPrompt =
        """
You are a Senior Agricultural Quality Control Specialist specializing in Poultry Incubation.

DATA:
- Total Eggs: $total
- Fertile Eggs: $fertile
- Infertile Eggs: $infertile
- Fertility Rate: $rate%

TASK:
Generate a comprehensively structured, professional analytical report containing:
1. Executive Summary (detailed paragraph)
2. Biological Interpretation of a $rate% fertility rate (detailed explanation)
3. Actionable Recommendations (numbered list)

IMPORTANT STYLE RULES:
- Scientific, brief, and to the point.
- Keep the entire report incredibly short, STRICTLY under 150 words total.
- Use plain English text only. DO NOT use fancy formatting, LaTeX, `\\(`, `\\)`, or `\$\$` symbols.
- DO NOT act like an AI or an assistant. Start immediately with the report content.
- Use **bold text** for headings.
- DO NOT use any markdown tables or giant '#' headings.
""";

    final shortPrompt =
        """
Write an extremely short poultry egg fertility report for: Total=$total, Fertile=$fertile, Infertile=$infertile, Rate=$rate%.
Include: 1-sentence summary, 1-sentence interpretation, 2 short actionable recommendations.
Use plain text. STRCITLY under 150 words. Start immediately. Use **bold text** for headings. NO markdown tables. NO large '#' headings. NO LaTeX symbols.
""";

    final payload = {
      "contents": [
        {
          "role": "user",
          "parts": [
            {"text": reportPrompt},
            {
              "inline_data": {"mime_type": "image/jpeg", "data": imgB64},
            },
          ],
        },
      ],
      "generationConfig": {"maxOutputTokens": 3000, "temperature": 0.3},
    };

    try {
      return await _post(payload);
    } on _TruncatedResponseException {
      // First attempt was cut off — retry with a shorter prompt (no image to save tokens)
      final retryPayload = {
        "contents": [
          {
            "role": "user",
            "parts": [
              {"text": shortPrompt},
            ],
          },
        ],
        "generationConfig": {"maxOutputTokens": 3000, "temperature": 0.3},
      };
      return await _post(retryPayload);
    }
  }

  /// Poultech domain-restricted assistant
  static Future<String> getAssistantResponse(String query) async {
    final assistantPrompt =
        """
You are the Poultech Knowledge Assistant.
You are an expert in poultry farming, avian embryology, and egg incubation.

Rules:
- Answer clearly but extremely concisely.
- STRICT LENGTH LIMIT: Your entire response MUST be under 150 words. Do not exceed this limit.
- Provide a pure text answer. DO NOT use LaTeX, math symbols like `\\(`, `\\)`, `\\/`, or markdown math blocks. Use standard plain text (e.g. '10%').
- DO NOT act like a generic AI. Start your answer immediately.
- If unrelated to poultry or eggs, politely redirect.

User Question:
"$query"
""";

    final payload = {
      "contents": [
        {
          "role": "user",
          "parts": [
            {"text": assistantPrompt},
          ],
        },
      ],
      "generationConfig": {"maxOutputTokens": 3000, "temperature": 0.5},
    };

    try {
      return await _post(payload);
    } on _TruncatedResponseException catch (e) {
      return "${e.partialText}\n\n_(Response was cut short. Please try asking again.)_";
    }
  }
}

/// Thrown when Gemini returns finishReason == MAX_TOKENS (truncated output).
class _TruncatedResponseException implements Exception {
  final String partialText;
  _TruncatedResponseException(this.partialText);
}
