import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'gemini.dart';
import 'store.dart';

/// Where Jarvis's thinking happens, in the order you choose:
///  phone   rules on this phone (no AI): simple notes, quick answers. Free, offline, instant.
///  server  your own model behind an OpenAI-style API (Ollama, llama.cpp, vLLM), e.g. Gemma 4 12B.
///  api     any hosted OpenAI-style API (OpenRouter, Groq…) or Google Gemini.
/// Each AI request tries the AI entries top to bottom and falls back to the next if one fails.
/// Keys stay on this phone (local settings), never in the synced data.
class AI {
  static List<Map<String, dynamic>> providers(Store s) {
    final saved = s.settings['ai'];
    if (saved is List && saved.isNotEmpty) return saved.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
    return [
      {'id': 'phone', 'type': 'phone', 'name': 'On this phone', 'on': s.settings['local'] != false},
      {'id': 'gemini', 'type': 'gemini', 'name': 'Google Gemini', 'on': true},
    ];
  }

  static void save(Store s, List<Map<String, dynamic>> p) {
    s.settings['ai'] = p;
    s.save();
  }

  static String? key(Store s, Map<String, dynamic> p) =>
      p['type'] == 'gemini' ? (s.apiKey.isEmpty ? null : s.apiKey) : s.local('ai_key_${p['id']}');

  /// Ready to answer: switched on and set up.
  static bool ready(Store s, Map<String, dynamic> p) {
    if (p['on'] != true) return false;
    return switch (p['type']) {
      'phone' => true,
      'gemini' => s.apiKey.isNotEmpty,
      _ => ((p['url'] as String?) ?? '').isNotEmpty && ((p['model'] as String?) ?? '').isNotEmpty,
    };
  }

  /// Any AI (not just phone rules) is set up.
  static bool available(Store s) => providers(s).any((p) => p['type'] != 'phone' && ready(s, p));

  static bool phoneOn(Store s) => providers(s).any((p) => p['type'] == 'phone' && p['on'] == true);

  /// Phone rules come before every AI: simple notes never leave the phone.
  static bool phoneFirst(Store s) {
    for (final p in providers(s)) {
      if (!ready(s, p)) continue;
      return p['type'] == 'phone';
    }
    return false;
  }

  /// The name of the AI that answered last (for "answered by …").
  static String? lastUsed;

  /// Sends one prompt to the first AI that answers. With [json] the answer must be JSON. An [image] (or a PDF,
  /// with [mime]) goes along; AIs that cannot take it are skipped.
  static Future<String> generate(Store s, String prompt, {required bool json, Uint8List? image, String mime = 'image/jpeg'}) async {
    final errors = <String>[];
    for (final p in providers(s)) {
      if (p['type'] == 'phone' || !ready(s, p)) continue;
      if (image != null && p['type'] != 'gemini' && !mime.startsWith('image/')) continue; // only Gemini reads PDFs
      try {
        final out = p['type'] == 'gemini'
            ? await Gemini.generate(s, prompt, json: json, image: image, mime: mime)
            : await _openai(p, key(s, p), prompt, json: json, image: image, mime: mime);
        lastUsed = p['name'] as String?;
        return out;
      } catch (e) {
        errors.add('${p['name']}: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
    if (errors.isEmpty) throw Exception('No AI is set up. Add Gemini, a server or an API in Settings, AI models.');
    throw Exception(errors.join('; '));
  }

  /// One call to an OpenAI-style chat API (Ollama's /v1, llama.cpp server, vLLM, OpenRouter, Groq…).
  static Future<String> _openai(Map<String, dynamic> p, String? key, String prompt,
      {required bool json, Uint8List? image, String mime = 'image/jpeg'}) async {
    var base = (p['url'] as String).trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    final content = image == null
        ? prompt
        : [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:$mime;base64,${base64Encode(image)}'},
            },
          ];
    final res = await http
        .post(
          Uri.parse('$base/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            if (key != null && key.isNotEmpty) 'Authorization': 'Bearer $key',
          },
          body: jsonEncode({
            'model': p['model'],
            'messages': [
              {'role': 'user', 'content': content},
            ],
            'temperature': json ? 0.1 : 0.4,
            if (json) 'response_format': {'type': 'json_object'},
          }),
        )
        .timeout(const Duration(seconds: 90));
    if (res.statusCode != 200) {
      var why = res.body;
      if (why.length > 160) why = why.substring(0, 160);
      throw Exception('error ${res.statusCode}: $why');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    var text = (data['choices'][0]['message']['content'] as String?) ?? '';
    // Thinking models may put their reasoning first; only the answer matters.
    text = text.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
    if (json) {
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start >= 0 && end > start) text = text.substring(start, end + 1);
    }
    return text;
  }

  /// A quick check that an entry answers, for the Test button.
  static Future<String> test(Store s, Map<String, dynamic> p) async {
    final out = p['type'] == 'gemini'
        ? await Gemini.generate(s, 'Reply with the JSON {"ok": true}', json: true)
        : await _openai(p, key(s, p), 'Reply with the JSON {"ok": true}', json: true);
    return out.contains('ok') ? 'Works.' : 'Answered, but oddly: $out';
  }
}
