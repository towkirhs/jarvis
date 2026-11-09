import 'dart:convert';

/// A block written by ChatGPT (or any AI) for Jarvis: the line "JARVIS v1" followed by the same JSON
/// Jarvis's own AI returns ({reply, remember, items}). Pasted or shared into Jarvis, it is applied as is,
/// with no AI call. Pure Dart, so it can be tested on its own.
class ChatGptBlock {
  static final _marker = RegExp(r'JARVIS\s+v(\d+)', caseSensitive: false);

  /// True when the text carries a block (so it is never skipped as an ordinary note).
  static bool has(String raw) => _marker.hasMatch(raw);

  /// The parsed block, or null when there is no marker. Throws [FormatException] when the block is broken.
  static Map<String, dynamic>? parse(String raw) {
    final m = _marker.firstMatch(raw);
    if (m == null) return null;
    if (m.group(1) != '1') throw FormatException('this Jarvis reads version 1 blocks, not v${m.group(1)}');
    final rest = raw.substring(m.end);
    final start = rest.indexOf('{');
    final end = rest.lastIndexOf('}');
    if (start < 0 || end <= start) throw const FormatException('no JSON after "JARVIS v1"');
    final data = jsonDecode(rest.substring(start, end + 1));
    if (data is! Map) throw const FormatException('the JSON must be an object');
    final out = Map<String, dynamic>.from(data);
    final items = out['items'];
    if (items != null && items is! List) throw const FormatException('"items" must be a list');
    // You checked it with ChatGPT already, so items are sure unless the block says otherwise.
    out['items'] = [
      for (final i in (items as List?) ?? const [])
        if (i is Map) {...Map<String, dynamic>.from(i), 'confidence': i['confidence'] ?? 1},
    ];
    return out;
  }
}
