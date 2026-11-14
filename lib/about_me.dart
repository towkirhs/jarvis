/// What Jarvis knows about how you talk: your own words (what speech-to-text hears → what you meant)
/// and your profile files (short notes about you, usually written by your ChatGPT Project).
/// Pure Dart, so it can be tested on its own.
///
/// Collection `words`: {id, from, to}. Collection `profile`: {id, name, keys: [word], always: bool, text}.
class Words {
  /// [text] with every word or phrase in [words] replaced by what you meant. Matches whole words, any case;
  /// longer phrases go first so "jar bis" wins over "bis".
  static String fix(String text, List<Map<String, dynamic>> words) {
    final list = [
      for (final w in words)
        if ('${w['from'] ?? ''}'.trim().isNotEmpty) w,
    ]..sort((a, b) => '${b['from']}'.length.compareTo('${a['from']}'.length));
    var out = text;
    for (final w in list) {
      final from = '${w['from']}'.trim();
      final pattern = RegExp('(?<![\\p{L}\\p{N}])${RegExp.escape(from).replaceAll(' ', r'\s+')}(?![\\p{L}\\p{N}])',
          caseSensitive: false, unicode: true);
      out = out.replaceAll(pattern, '${w['to']}');
    }
    return out;
  }

  /// When [after] differs from [before] in one run of 1 to 3 words, that change (heard → meant); otherwise null.
  /// Used to offer adding a correction you made by editing a message.
  static (String, String)? change(String before, String after) {
    final a = before.trim().split(RegExp(r'\s+'));
    final b = after.trim().split(RegExp(r'\s+'));
    var head = 0;
    while (head < a.length && head < b.length && a[head] == b[head]) {
      head++;
    }
    var tail = 0;
    while (tail < a.length - head && tail < b.length - head && a[a.length - 1 - tail] == b[b.length - 1 - tail]) {
      tail++;
    }
    final from = a.sublist(head, a.length - tail);
    final to = b.sublist(head, b.length - tail);
    if (from.isEmpty || to.isEmpty || from.length > 3 || to.length > 3) return null;
    String clean(List<String> w) => w.join(' ').replaceAll(RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true), '');
    final f = clean(from);
    final t = clean(to);
    if (f.isEmpty || t.isEmpty || f.toLowerCase() == t.toLowerCase()) return null;
    return (f, t);
  }
}

class ProfileFiles {
  static Set<String> _words(String t) =>
      t.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((w) => w.isNotEmpty).toSet();

  /// The files that fit [note]: those marked "always", then those one of whose key words is in the note
  /// (a key of several words must appear as written). Stops before [maxChars], so a small model keeps room.
  static List<Map<String, dynamic>> pick(List<Map<String, dynamic>> files, String note, {int maxChars = 2400}) {
    final words = _words(note);
    final low = note.toLowerCase();
    bool hits(Map f) => ((f['keys'] as List?) ?? const []).any((k) {
          final key = '$k'.trim().toLowerCase();
          if (key.isEmpty) return false;
          return key.contains(' ') ? low.contains(key) : words.contains(key);
        });
    final out = <Map<String, dynamic>>[];
    var chars = 0;
    for (final f in [
      ...files.where((f) => f['always'] == true),
      ...files.where((f) => f['always'] != true && hits(f)),
    ]) {
      final len = '${f['text'] ?? ''}'.length;
      if (len == 0 || chars + len > maxChars) continue;
      out.add(f);
      chars += len;
    }
    return out;
  }

  /// The picked files for the AI's prompt.
  static String forPrompt(List<Map<String, dynamic>> picked) =>
      [for (final f in picked) '## ${f['name']}\n${'${f['text']}'.trim()}'].join('\n\n');

  /// The files as one text to paste into ChatGPT, so it updates them instead of starting again.
  static String forChatGpt(List<Map<String, dynamic>> files, List<Map<String, dynamic>> words) {
    final b = StringBuffer('My Jarvis profile files as they are now. Update them from what you know about me, '
        'keep each one short, and send back only the files that changed as a JARVIS v1 block with "profile" items.\n\n');
    for (final f in files) {
      b.writeln('### ${f['name']}${f['always'] == true ? ' (always used)' : ''}');
      b.writeln('Key words: ${((f['keys'] as List?) ?? const []).join(', ')}');
      b.writeln('${f['text'] ?? ''}'.trim());
      b.writeln();
    }
    if (words.isNotEmpty) {
      b.writeln('### My words (what the phone hears → what I meant)');
      for (final w in words) {
        b.writeln('${w['from']} → ${w['to']}');
      }
    }
    return b.toString().trim();
  }

  /// A file from a ChatGPT "profile" item, or null when it has no name or text.
  static Map<String, dynamic>? fromBlock(Map p) {
    final name = '${p['title'] ?? p['name'] ?? ''}'.trim();
    final text = '${p['text'] ?? p['description'] ?? ''}'.trim();
    if (name.isEmpty || text.isEmpty) return null;
    return {
      'name': name,
      'keys': [for (final k in (p['keys'] as List?) ?? const []) '$k'.trim()]..removeWhere((k) => k.isEmpty),
      'always': p['always'] == true,
      'text': text,
    };
  }
}
