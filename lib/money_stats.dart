/// The sums behind Money's Stats and Goals tabs. Pure Dart, so it can be tested on its own.
///
/// A transaction: {type: income | expense | transfer, amount, account, toAccount, cat, ts}.
/// An account: {name, initial, savings: bool}. A goal (collection `goals`):
/// {id, name, target, due (ms or null), account (name, or null), adds: [{ts, amount}], start (ms)}.
/// A goal linked to an account counts that account's balance; otherwise what was added to it by hand.
class MonthSum {
  const MonthSum(this.month, this.income, this.expense);
  final DateTime month;
  final num income;
  final num expense;
  num get net => income - expense;

  /// Share of income kept, 0 to 1 (0 when there was no income).
  double get savingsRate => income <= 0 ? 0 : (net / income).clamp(-1.0, 1.0).toDouble();
}

class MoneyStats {
  static DateTime _monthOf(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return DateTime(d.year, d.month);
  }

  /// Income and spending of [months] months, oldest first, ending with the month of [last].
  static List<MonthSum> months(Iterable<Map> txs, DateTime last, {int months = 6}) {
    final out = <MonthSum>[];
    for (var k = months - 1; k >= 0; k--) {
      final m = DateTime(last.year, last.month - k);
      num inc = 0, exp = 0;
      for (final t in txs) {
        if (_monthOf(t['ts'] as int) != m) continue;
        if (t['type'] == 'income') inc += t['amount'] as num;
        if (t['type'] == 'expense') exp += t['amount'] as num;
      }
      out.add(MonthSum(m, inc, exp));
    }
    return out;
  }

  /// Spending in [month] by the end of it at the pace so far. For a past month, what was spent.
  static num forecast(Iterable<Map> txs, DateTime month, DateTime now) {
    final m = DateTime(month.year, month.month);
    final spent = months(txs, m, months: 1).single.expense;
    if (m != DateTime(now.year, now.month)) return spent;
    final daysIn = DateTime(m.year, m.month + 1, 0).day;
    return spent / now.day * daysIn;
  }

  /// Average monthly spending over the [n] full months before [month].
  static num averageSpend(Iterable<Map> txs, DateTime month, {int n = 3}) {
    final list = months(txs, DateTime(month.year, month.month - 1), months: n);
    final used = list.where((m) => m.income > 0 || m.expense > 0).toList();
    if (used.isEmpty) return 0;
    return used.fold<num>(0, (a, m) => a + m.expense) / used.length;
  }

  /// Categories whose spending in [month] moved most against their average of the 3 months before:
  /// (category, this month, average), biggest change first.
  static List<(String, num, num)> categoryChanges(Iterable<Map> txs, DateTime month, {int take = 4}) {
    final m = DateTime(month.year, month.month);
    final now = <String, num>{};
    final before = <String, num>{};
    for (final t in txs) {
      if (t['type'] != 'expense') continue;
      final at = _monthOf(t['ts'] as int);
      final cat = '${t['cat'] ?? 'Other'}';
      if (at == m) {
        now[cat] = (now[cat] ?? 0) + (t['amount'] as num);
      } else if (!at.isBefore(DateTime(m.year, m.month - 3)) && at.isBefore(m)) {
        before[cat] = (before[cat] ?? 0) + (t['amount'] as num);
      }
    }
    final out = [
      for (final c in {...now.keys, ...before.keys}) (c, now[c] ?? 0, (before[c] ?? 0) / 3),
    ]..sort((a, b) => (b.$2 - b.$3).abs().compareTo((a.$2 - a.$3).abs()));
    return out.where((e) => (e.$2 - e.$3).abs() > 0).take(take).toList();
  }

  /// Spending by weekday (Monday first) in [month].
  static List<num> byWeekday(Iterable<Map> txs, DateTime month) {
    final m = DateTime(month.year, month.month);
    final out = List<num>.filled(7, 0);
    for (final t in txs) {
      if (t['type'] != 'expense' || _monthOf(t['ts'] as int) != m) continue;
      final d = DateTime.fromMillisecondsSinceEpoch(t['ts'] as int);
      out[d.weekday - 1] += t['amount'] as num;
    }
    return out;
  }

  /// Total of all accounts at the end of each of [n] months, oldest first, ending with [last]'s month.
  /// [only] limits it to those account names (for savings).
  static List<num> netWorth(Iterable<Map> txs, Iterable<Map> accounts, DateTime last, {int n = 6, Set<String>? only}) {
    final names = {for (final a in accounts) '${a['name']}'};
    final counted = only ?? names;
    final start = accounts.where((a) => counted.contains('${a['name']}')).fold<num>(0, (a, x) => a + ((x['initial'] as num?) ?? 0));
    final sorted = txs.toList()..sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));
    final out = <num>[];
    for (var k = n - 1; k >= 0; k--) {
      final end = DateTime(last.year, last.month - k + 1).millisecondsSinceEpoch;
      num total = start;
      for (final t in sorted) {
        if ((t['ts'] as int) >= end) break;
        final a = t['amount'] as num;
        final from = counted.contains('${t['account']}');
        final to = counted.contains('${t['toAccount']}');
        if (t['type'] == 'income' && from) total += a;
        if (t['type'] == 'expense' && from) total -= a;
        if (t['type'] == 'transfer') {
          if (from) total -= a;
          if (to) total += a;
        }
      }
      out.add(total);
    }
    return out;
  }

  /// How many months [balance] would last at [monthlySpend]; null when nothing is spent.
  static double? runway(num balance, num monthlySpend) => monthlySpend <= 0 ? null : (balance / monthlySpend).toDouble();

  /// What a goal has so far: its account's balance when linked, else what was added to it.
  static num goalSaved(Map goal, num Function(String account) balanceOf) {
    final acc = goal['account'] as String?;
    if (acc != null && acc.isNotEmpty) return balanceOf(acc);
    return ((goal['adds'] as List?) ?? const []).fold<num>(0, (a, x) => a + ((x as Map)['amount'] as num));
  }

  /// How a goal is going: share done, what is left, what it needs a month to make its date, and the
  /// pace so far (a month) since it started. `onTrack` is null when it has no date.
  static ({double done, num left, num? perMonth, num pace, bool? onTrack, DateTime? eta}) goal(
      Map goal, num saved, DateTime now) {
    final target = (goal['target'] as num?) ?? 0;
    final left = target - saved;
    final done = target <= 0 ? 0.0 : (saved / target).clamp(0.0, 1.0).toDouble();
    final start = DateTime.fromMillisecondsSinceEpoch((goal['start'] as int?) ?? now.millisecondsSinceEpoch);
    final monthsIn = (now.difference(start).inDays / 30.44).clamp(1.0, 1200.0);
    final startSaved = (goal['startSaved'] as num?) ?? 0;
    final pace = (saved - startSaved) / monthsIn;
    num? perMonth;
    bool? onTrack;
    if (goal['due'] is int && left > 0) {
      final due = DateTime.fromMillisecondsSinceEpoch(goal['due'] as int);
      final monthsLeft = (due.difference(now).inDays / 30.44).clamp(0.0, 1200.0);
      perMonth = monthsLeft < 1 ? left : left / monthsLeft;
      onTrack = pace >= perMonth;
    }
    DateTime? eta;
    if (left > 0 && pace > 0) eta = now.add(Duration(days: (left / pace * 30.44).round()));
    return (done: done, left: left < 0 ? 0 : left, perMonth: perMonth, pace: pace, onTrack: left <= 0 ? true : onTrack, eta: left <= 0 ? now : eta);
  }
}
