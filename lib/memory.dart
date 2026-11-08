import 'dart:math';

/// What Jarvis remembers about you, kept on the phone and handed to whichever AI answers.
///
/// A memory ('memories') is {id, text, ts: first saved, last: last seen, n: times seen, pin}.
/// The AI returns lasting facts with each note; the same fact coming up again counts up [n], which is how
/// repetitive things (your team, your routines, the people you mention) rise to the top. Pure Dart.
class Memory {
  /// The most memories kept; the least used unpinned ones go first.
  static const maxKept = 200;

  /// The longest one fact can be.
  static const maxText = 140;

  static const _stop = {
    'the', 'and', 'for', 'with', 'that', 'this', 'from', 'are', 'was', 'were', 'has', 'have', 'had', 'his',
    'her', 'their', 'its', 'you', 'your', 'who', 'what', 'when', 'where', 'how', 'any', 'does', 'did',
    'not', 'but', 'about', 'into', 'than', 'then', 'they', 'them', 'will', 'can', 'one', 'now', 'user',
    'person', 'usually', 'always', 'often',
  };

  static Set<String> words(String text) => RegExp(r"[a-z0-9ঀ-৿']+")
      .allMatches(text.toLowerCase())
      .map((m) => m.group(0)!)
      .where((w) => w.length >= 3 && !_stop.contains(w))
      .toSet();

  /// The same fact in other words: one holds most of the other's words.
  static bool same(String a, String b) {
    final x = words(a), y = words(b);
    if (x.isEmpty || y.isEmpty) return a.trim().toLowerCase() == b.trim().toLowerCase();
    final both = x.intersection(y).length;
    return both / min(x.length, y.length) >= 0.75 && both / max(x.length, y.length) >= 0.5;
  }

  /// A fact fit to keep: one short line, and nothing that looks like a secret.
  static String? clean(Object? raw) {
    var t = (raw?.toString() ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length < 4) return null;
    if (RegExp(r'\b(password|passcode|pin code|otp|api key|secret|cvv|\d{4}[ -]?\d{4}[ -]?\d{4})\b', caseSensitive: false).hasMatch(t)) {
      return null;
    }
    if (t.length > maxText) t = '${t.substring(0, maxText - 1).trimRight()}…';
    return t;
  }

  /// Adds [facts] to [memories]: one already there is counted again, the rest are new. Returns how many were new.
  static int merge(List<Map<String, dynamic>> memories, Iterable<Object?> facts,
      {required int now, required int Function() nextId}) {
    var added = 0;
    final seen = <Map<String, dynamic>>{};
    for (final raw in facts) {
      final t = clean(raw);
      if (t == null) continue;
      final known = memories.where((m) => same(m['text'] as String, t)).firstOrNull;
      if (known != null) {
        // Said twice in one note still counts once.
        if (seen.add(known)) {
          known['n'] = ((known['n'] as int?) ?? 1) + 1;
          known['last'] = now;
        }
        continue;
      }
      final m = {'id': nextId(), 'text': t, 'ts': now, 'last': now, 'n': 1, 'pin': false};
      memories.add(m);
      seen.add(m);
      added++;
    }
    if (memories.length > maxKept) {
      final order = [...memories.where((m) => m['pin'] != true)]
        ..sort((a, b) => _keep(a).compareTo(_keep(b)));
      for (final m in order.take(memories.length - maxKept)) {
        memories.remove(m);
      }
    }
    return added;
  }

  /// How worth keeping: often seen, and seen lately.
  static double _keep(Map<String, dynamic> m) => ((m['n'] as int?) ?? 1) * 1000.0 + ((m['last'] as int?) ?? 0) / 1e9;

  /// The memories to give the AI with [note]: pinned ones, ones that share words with the note, and the ones you
  /// repeat most, up to [maxChars].
  static List<String> pick(List<Map<String, dynamic>> memories, String note, {int maxChars = 1400}) {
    final noteWords = words(note);
    double score(Map<String, dynamic> m) {
      final n = (m['n'] as int?) ?? 1;
      final hit = words(m['text'] as String).intersection(noteWords).length;
      return (m['pin'] == true ? 1000 : 0) + hit * 30 + (n >= 3 ? log(n) * 4 : 0) + _keep(m) / 1e6;
    }

    final ranked = [for (final m in memories) if (score(m) >= 1) m]..sort((a, b) => score(b).compareTo(score(a)));
    final out = <String>[];
    var chars = 0;
    for (final m in ranked) {
      final line = m['text'] as String;
      if (chars + line.length > maxChars) continue;
      out.add(line);
      chars += line.length + 3;
    }
    return out;
  }
}
