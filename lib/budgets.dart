/// Monthly budgets per expense category, and how much of each is spent. Pure Dart, tested on its own.
///
/// Budgets live in settings['budgets'] as {category: amount per month}.
library;

class BudgetRow {
  const BudgetRow(this.category, this.spent, this.limit);
  final String category;
  final num spent, limit;
  double get ratio => limit <= 0 ? 0 : spent / limit;
  num get left => limit - spent;
}

class Budgets {
  static Map<String, num> of(Map<String, dynamic> settings) {
    final b = settings['budgets'];
    if (b is! Map) return const {};
    return {for (final e in b.entries) if (e.value is num && (e.value as num) > 0) '${e.key}': e.value as num};
  }

  /// Each budget with what was spent on it in [day]'s calendar month, fullest first.
  static List<BudgetRow> month(List<Map<String, dynamic>> tx, Map<String, num> budgets, DateTime day) {
    final from = DateTime(day.year, day.month).millisecondsSinceEpoch;
    final to = DateTime(day.year, day.month + 1).millisecondsSinceEpoch;
    final spent = <String, num>{};
    for (final t in tx) {
      final ts = t['ts'];
      if (t['type'] != 'expense' || ts is! int || ts < from || ts >= to) continue;
      final cat = '${t['cat']}';
      spent[cat] = (spent[cat] ?? 0) + (t['amount'] as num);
    }
    return [for (final e in budgets.entries) BudgetRow(e.key, spent[e.key] ?? 0, e.value)]
      ..sort((a, b) => b.ratio.compareTo(a.ratio));
  }

  /// The line to say when an expense of [amount] took [category] past 80% or past its budget, else null.
  static String? crossed(List<Map<String, dynamic>> tx, Map<String, num> budgets, String category, num amount, DateTime day) {
    final limit = budgets[category];
    if (limit == null) return null;
    final row = month(tx, {category: limit}, day).single;
    final before = (row.spent - amount) / limit;
    final now = row.ratio;
    String money(num n) => '৳${n.round()}';
    if (before < 1 && now >= 1) return '$category is over its budget: ${money(row.spent)} of ${money(limit)} this month.';
    if (before < 0.8 && now >= 0.8) return '$category: ${(now * 100).round()}% of this month\'s budget used, ${money(row.left)} left.';
    return null;
  }

  /// Open tasks to buy something: they carry a `cost`, or their title starts with "buy". Cheapest last.
  static List<Map<String, dynamic>> toBuy(List<Map<String, dynamic>> items) => [
        for (final i in items)
          if (i['kind'] == 'task' && i['status'] == 'open' && (i['cost'] is num || '${i['title']}'.toLowerCase().startsWith('buy ')))
            i,
      ]..sort((a, b) => ((b['cost'] as num?) ?? 0).compareTo((a['cost'] as num?) ?? 0));
}
