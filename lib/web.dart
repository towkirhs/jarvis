import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai.dart';
import 'store.dart';

/// Searching the internet for things your own data cannot answer (news, weather, prices, scores, facts).
/// Only the search question leaves the phone, never your notes. It uses AIs that can search:
/// Google Gemini (Google Search) and Groq's gpt-oss models (browser search), in your AI order.
class Web {
  /// Searching the web is on unless switched off in Settings, AI models.
  static bool on(Store s) => s.settings['web'] != false;

  /// The question in "search for X", "google X", "look up X online"; null if the note does not ask to search.
  static String? asked(String raw) {
    final m = RegExp(
      r'^(?:(?:hey|ok) jarvis[,!]?\s+)?(?:please\s+)?'
      r'(?:search(?: the (?:web|internet|net))?(?: online)?(?: for)?|google|look up|find online|search online for)\s+(.+?)\s*(?:online|on the (?:web|internet))?[.?!]*$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    final q = m?.group(1)?.trim();
    return q == null || q.isEmpty ? null : q;
  }

  /// The AIs in your order that can search the web.
  static List<Map<String, dynamic>> searchers(Store s) => [
        for (final p in AI.providers(s))
          if (AI.ready(s, p) && (p['type'] == 'gemini' || _isGroq(p))) p,
      ];

  static bool _isGroq(Map<String, dynamic> p) =>
      p['type'] == 'openai' && ((p['url'] as String?) ?? '').contains('api.groq.com');

  static bool available(Store s) => searchers(s).isNotEmpty;

  /// Searches and answers [question] in a few sentences, with the pages it used.
  static Future<WebAnswer> search(Store s, String question) async {
    final list = searchers(s);
    if (list.isEmpty) {
      throw Exception('To search the web, add your Gemini key or a Groq API in Settings, AI models.');
    }
    final prompt = 'Search the web and answer in two to four short sentences, plain text, no markdown. '
        'Today is ${dayKey(DateTime.now())}. Question: $question';
    final errors = <String>[];
    for (final p in list) {
      try {
        final a = p['type'] == 'gemini' ? await _gemini(s, prompt) : await _groq(p, AI.key(s, p), prompt);
        AI.lastUsed = '${p['name']}, web';
        return a;
      } catch (e) {
        errors.add('${p['name']}: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
    throw Exception(errors.join('; '));
  }

  static Future<WebAnswer> _gemini(Store s, String prompt) async {
    final model = (s.settings['model'] as String?) ?? 'gemini-2.5-flash-lite';
    final res = await http
        .post(
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
            'tools': [
              {'google_search': {}},
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) throw Exception('error ${res.statusCode}');
    return parseGemini(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  static Future<WebAnswer> _groq(Map<String, dynamic> p, String? key, String prompt) async {
    var base = (p['url'] as String).trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    // Browser search only works on the gpt-oss models.
    final model = '${p['model']}'.contains('gpt-oss') ? p['model'] : 'openai/gpt-oss-120b';
    final res = await http
        .post(
          Uri.parse('$base/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            if (key != null && key.isNotEmpty) 'Authorization': 'Bearer $key',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'user', 'content': prompt},
            ],
            'tools': [
              {'type': 'browser_search'},
            ],
            'tool_choice': 'required',
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      var why = res.body;
      if (why.length > 160) why = why.substring(0, 160);
      throw Exception('error ${res.statusCode}: $why');
    }
    return parseOpenAi(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Gemini's answer and the pages Google Search found (grounding chunks).
  static WebAnswer parseGemini(Map<String, dynamic> data) {
    final cand = (data['candidates'] as List).first as Map<String, dynamic>;
    final parts = ((cand['content'] as Map?)?['parts'] as List?) ?? const [];
    final text = parts.map((e) => (e as Map)['text'] ?? '').join().trim();
    final chunks = ((cand['groundingMetadata'] as Map?)?['groundingChunks'] as List?) ?? const [];
    final sources = <WebSource>[];
    for (final c in chunks) {
      final web = (c as Map)['web'] as Map?;
      final url = web?['uri'] as String?;
      if (url == null || sources.any((x) => x.url == url)) continue;
      sources.add(WebSource((web?['title'] as String?) ?? Uri.parse(url).host, url));
    }
    if (text.isEmpty) throw Exception('empty answer');
    return WebAnswer(text, sources.take(5).toList());
  }

  /// An OpenAI-style answer; the pages are the links in the text (Groq does not list them separately).
  static WebAnswer parseOpenAi(Map<String, dynamic> data) {
    var text = (((data['choices'] as List).first as Map)['message']['content'] as String?) ?? '';
    text = text.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
    final sources = <WebSource>[];
    for (final m in RegExp(r'https?://[^\s)\]>"]+').allMatches(text)) {
      final url = m.group(0)!.replaceAll(RegExp(r'[.,;]+$'), '');
      if (!sources.any((x) => x.url == url)) sources.add(WebSource(Uri.parse(url).host, url));
    }
    // Markdown links and bare links read badly in a chat bubble: keep the words, the links go below.
    text = text
        // Citation markers like 【3†L5-L11】 that the search model leaves in its answer.
        .replaceAll(RegExp(r'\s*【[^】]*】'), '')
        .replaceAllMapped(RegExp(r'\[([^\]]+)\]\(https?://[^)]+\)'), (m) => m.group(1)!)
        .replaceAll(RegExp(r'\(?https?://[^\s)]+\)?'), '')
        .replaceAll(RegExp(r'[*#]'), '')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
    if (text.isEmpty) throw Exception('empty answer');
    return WebAnswer(text, sources.take(5).toList());
  }
}

class WebSource {
  const WebSource(this.title, this.url);
  final String title;
  final String url;
  Map<String, String> toJson() => {'title': title, 'url': url};
}

class WebAnswer {
  const WebAnswer(this.text, this.sources);
  final String text;
  final List<WebSource> sources;
}
