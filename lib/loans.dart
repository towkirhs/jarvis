/// Money lent to and borrowed from people. A transaction is `{person, type: 'gave' | 'took', amount, why, method, ts, note}`.
/// What I gave minus what I took is what the person owes me; below zero, I owe them.
class Loans {
  static const methods = ['Cash', 'bKash', 'Nagad', 'Rocket', 'Bank', 'Other'];
  static const ranges = ['all', 'today', 'week', 'month'];

  static num balance(int person, Iterable<Map<String, dynamic>> txs) => txs
      .where((t) => t['person'] == person)
      .fold<num>(0, (a, t) => a + (t['type'] == 'gave' ? 1 : -1) * (t['amount'] as num));

  static ({num receive, int receiveFrom, num pay, int payTo}) totals(Iterable<int> people, Iterable<Map<String, dynamic>> txs) {
    num receive = 0, pay = 0;
    var from = 0, to = 0;
    for (final p in people) {
      final b = balance(p, txs);
      if (b > 0) {
        receive += b;
        from++;
      } else if (b < 0) {
        pay -= b;
        to++;
      }
    }
    return (receive: receive, receiveFrom: from, pay: pay, payTo: to);
  }

  static bool inRange(int ts, String range, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final start = switch (range) {
      'today' => today,
      'week' => today.subtract(Duration(days: now.weekday - 1)),
      'month' => DateTime(now.year, now.month),
      _ => null,
    };
    return start == null || !DateTime.fromMillisecondsSinceEpoch(ts).isBefore(start);
  }
}
