import 'dart:convert';

import 'package:http/http.dart' as http;

import 'store.dart';

class Gemini {
  /// Sends one prompt and returns the text answer. With json: true the model is asked for JSON.
  static Future<String> generate(Store s, String prompt, {required bool json}) async {
    final model = (s.settings['model'] as String?) ?? 'gemini-2.5-flash-lite';
    final res = await http.post(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
      headers: {'Content-Type': 'application/json', 'x-goog-api-key': s.apiKey},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': json
            ? {'responseMimeType': 'application/json', 'temperature': 0.1}
            : {'temperature': 0.4},
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Gemini error ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['candidates'][0]['content']['parts'][0]['text'] as String;
  }
}
