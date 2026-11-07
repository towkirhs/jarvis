import 'dart:math';

/// Finding the right passages in your Drive files, on the phone. Pure Dart, tested on its own.
/// Files are cut into overlapping chunks; a question is matched by its words (rarer words count more).
class DriveSearch {
  static const _stop = {
    'the', 'a', 'an', 'and', 'or', 'of', 'to', 'in', 'on', 'for', 'is', 'are', 'was', 'were', 'be', 'it', 'this',
    'that', 'with', 'as', 'at', 'by', 'from', 'what', 'which', 'who', 'how', 'when', 'where', 'why', 'do', 'does',
    'did', 'my', 'me', 'i', 'you', 'your', 'about', 'can', 'tell', 'say', 'says', 'there', 'any', 'have', 'has',
  };

  static List<String> words(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.length > 1 && !_stop.contains(w))
      .toList();

  /// Splits text into chunks of about [size] characters, cutting at paragraph or sentence ends, overlapping a little.
  static List<String> chunk(String text, {int size = 1200}) {
    final clean = text.replaceAll('\r', '').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    if (clean.isEmpty) return const [];
    final out = <String>[];
    var start = 0;
    while (start < clean.length) {
      var end = min(start + size, clean.length);
      if (end < clean.length) {
        final para = clean.lastIndexOf('\n\n', end);
        final sentence = clean.lastIndexOf('. ', end);
        final cut = para > start + size ~/ 2 ? para : (sentence > start + size ~/ 2 ? sentence + 1 : end);
        end = cut;
      }
      out.add(clean.substring(start, end).trim());
      if (end >= clean.length) break;
      start = max(end - 150, start + 1); // a little overlap so an answer split across chunks is still found
    }
    return out.where((c) => c.isNotEmpty).toList();
  }

  /// The best [limit] chunks for [question], as (file index, chunk index, score), best first.
  /// [files] is a list of chunk lists.
  static List<(int, int, double)> search(String question, List<List<String>> files, {int limit = 6}) {
    final q = words(question).toSet();
    if (q.isEmpty) return const [];
    // How many chunks each word appears in, so rare words weigh more.
    final df = <String, int>{};
    var total = 0;
    final bags = <List<Set<String>>>[];
    for (final f in files) {
      final fb = <Set<String>>[];
      for (final c in f) {
        final set = words(c).toSet();
        fb.add(set);
        total++;
        for (final w in q) {
          if (set.contains(w)) df[w] = (df[w] ?? 0) + 1;
        }
      }
      bags.add(fb);
    }
    final hits = <(int, int, double)>[];
    for (var i = 0; i < bags.length; i++) {
      for (var j = 0; j < bags[i].length; j++) {
        var score = 0.0;
        for (final w in q) {
          if (bags[i][j].contains(w)) score += log(1 + total / (df[w] ?? 1));
        }
        if (score > 0) hits.add((i, j, score));
      }
    }
    hits.sort((a, b) => b.$3.compareTo(a.$3));
    return hits.take(limit).toList();
  }
}
