/// Money that comes in regularly: tuition, a part-time or full-time job, anything paid by the month.
/// Pure Dart, tested on its own.
///
/// A source ('incomes'): {id, name, kind, amount: a month, start: 'YYYY-MM', end: 'YYYY-MM' or null, account}.
/// A payment ('incomePays'): {id, source, amount, ts}.
/// A month is owed to you once it has ended; what was paid is taken off the oldest months first.
class Income {
  static const kinds = {'tuition': 'Tuition', 'job': 'Full-time job', 'part': 'Part-time job', 'other': 'Other'};

  static String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  /// Whether the source still pays in [now]'s month.
  static bool active(Map src, DateTime now) {
    final k = _key(now);
    return (src['start'] as String).compareTo(k) <= 0 && (src['end'] == null || (src['end'] as String).compareTo(k) >= 0);
  }

  /// How many of its months have ended by [now].
  static int monthsEnded(Map src, DateTime now) {
    final p = (src['start'] as String).split('-');
    var d = DateTime(int.parse(p[0]), int.parse(p[1]));
    final thisMonth = DateTime(now.year, now.month);
    var n = 0;
    while (d.isBefore(thisMonth) && (src['end'] == null || _key(d).compareTo(src['end'] as String) <= 0)) {
      n++;
      d = DateTime(d.year, d.month + 1);
    }
    return n;
  }

  static num received(Map src, Iterable<Map> pays) =>
      pays.where((p) => p['source'] == src['id']).fold<num>(0, (a, p) => a + (p['amount'] as num));

  /// What the source owes you for months that have ended (below zero: paid ahead).
  static num due(Map src, Iterable<Map> pays, DateTime now) => monthsEnded(src, now) * (src['amount'] as num) - received(src, pays);

  /// What all active sources bring in a month.
  static num monthly(Iterable<Map> sources, DateTime now) =>
      sources.where((s) => active(s, now)).fold<num>(0, (a, s) => a + (s['amount'] as num));
}
