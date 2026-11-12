/// Keeps money categories tidy: one spelling per category, and rules that remember
/// "groceries means Food" so chat, SMS and typing all land in the same place.
/// A rule is stored as `settings.catRules['expense:groceries'] = 'Food'`.
class CatUse {
  CatUse(this.name, this.count, this.total);
  final String name;
  int count;
  num total;
}

class Cats {
  static String key(String c) => c.trim().toLowerCase();

  static String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// The category to save for [raw]: a rule if one matches, else the spelling already in [known]
  /// (most used first), else the name with a capital. An empty name stays empty.
  static String tidy(String raw, {required String type, required Map<String, dynamic> rules, required List<String> known}) {
    var name = raw.trim();
    if (name.isEmpty) return name;
    for (var i = 0; i < 8; i++) {
      final next = rules['$type:${key(name)}'] as String?;
      if (next == null || key(next) == key(name)) break;
      name = next.trim();
    }
    final k = key(name);
    for (final c in known) {
      if (key(c) == k) return c.trim();
    }
    return _capital(name);
  }

  /// Categories of [type] with how many entries and how much, most used first.
  static List<CatUse> used(Iterable<Map<String, dynamic>> txs, String type) {
    final by = <String, CatUse>{};
    for (final t in txs) {
      if (t['type'] != type) continue;
      final c = (t['cat'] as String?) ?? 'Other';
      final u = by.putIfAbsent(c, () => CatUse(c, 0, 0));
      u.count++;
      u.total += t['amount'] as num;
    }
    return by.values.toList()..sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : b.total.compareTo(a.total));
  }

  /// Groups of names that differ only by case or spaces.
  static List<List<CatUse>> lookAlikes(List<CatUse> used) {
    final by = <String, List<CatUse>>{};
    for (final u in used) {
      (by[key(u.name)] ??= []).add(u);
    }
    return by.values.where((g) => g.length > 1).toList();
  }

  /// Moves every [type] entry named [from] (any case) to [to], remembers the rule, and points rules that
  /// led to [from] at [to]. Returns how many entries moved.
  static int merge(Iterable<Map<String, dynamic>> txs, Map<String, dynamic> rules, String type, String from, String to) {
    if (key(from) == key(to)) return 0;
    var n = 0;
    for (final t in txs) {
      if (t['type'] == type && key((t['cat'] as String?) ?? '') == key(from)) {
        t['cat'] = to;
        n++;
      }
    }
    for (final e in rules.entries.toList()) {
      if (e.key.startsWith('$type:') && key(e.value as String) == key(from)) rules[e.key] = to;
    }
    rules['$type:${key(from)}'] = to;
    return n;
  }
}
