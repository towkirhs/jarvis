import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/money_stats.dart';

int ts(int y, int m, int d) => DateTime(y, m, d, 12).millisecondsSinceEpoch;
Map<String, dynamic> tx(String type, num amount, int when, {String account = 'Cash', String? to, String cat = 'Food'}) =>
    {'type': type, 'amount': amount, 'account': account, 'toAccount': to, 'cat': cat, 'ts': when};

void main() {
  final txs = [
    tx('income', 30000, ts(2026, 9, 1), cat: 'Salary'),
    tx('expense', 9000, ts(2026, 9, 10)),
    tx('income', 30000, ts(2026, 10, 1), cat: 'Salary'),
    tx('expense', 12000, ts(2026, 10, 10)),
    tx('expense', 1500, ts(2026, 10, 11), cat: 'Transport'),
    tx('income', 30000, ts(2026, 11, 1), cat: 'Salary'),
    tx('expense', 6000, ts(2026, 11, 5)),
    tx('transfer', 5000, ts(2026, 11, 6), to: 'Savings'),
  ];
  final accounts = [
    {'name': 'Cash', 'initial': 1000},
    {'name': 'Savings', 'initial': 20000, 'savings': true},
  ];

  test('months: income, spending, net and savings rate, oldest first', () {
    final m = MoneyStats.months(txs, DateTime(2026, 11), months: 3);
    expect(m.map((x) => x.month.month), [9, 10, 11]);
    expect(m[1].expense, 13500);
    expect(m[1].net, 16500);
    expect(m[1].savingsRate, 0.55);
  });

  test('forecast: this month at the pace so far; a past month is what was spent', () {
    expect(MoneyStats.forecast(txs, DateTime(2026, 11), DateTime(2026, 11, 15)), 12000); // 6000 in 15 of 30 days
    expect(MoneyStats.forecast(txs, DateTime(2026, 10), DateTime(2026, 11, 15)), 13500);
  });

  test('average spending of the months before, and which categories moved', () {
    expect(MoneyStats.averageSpend(txs, DateTime(2026, 11)), 11250); // (9000 + 13500) / 2 months with data
    final c = MoneyStats.categoryChanges(txs, DateTime(2026, 11));
    expect(c.first.$1, 'Food'); // 6000 against (9000 + 12000) / 3
    expect(c.first.$3, 7000);
  });

  test('net worth at each month end, and savings only', () {
    expect(MoneyStats.netWorth(txs, accounts, DateTime(2026, 11), n: 3), [42000, 58500, 82500]);
    expect(MoneyStats.netWorth(txs, accounts, DateTime(2026, 11), n: 2, only: {'Savings'}), [20000, 25000]);
  });

  test('runway: months the money lasts', () {
    expect(MoneyStats.runway(60000, 12000), 5);
    expect(MoneyStats.runway(60000, 0), isNull);
  });

  test('a goal: from its account or from what was added; what it needs a month; whether it is on track', () {
    final now = DateTime(2026, 11, 15);
    final laptop = {
      'name': 'Laptop', 'target': 100000, 'start': DateTime(2026, 8, 1).millisecondsSinceEpoch,
      'due': DateTime(2027, 5, 15).millisecondsSinceEpoch,
      'adds': [{'ts': 0, 'amount': 20000}, {'ts': 0, 'amount': 20000}],
    };
    final saved = MoneyStats.goalSaved(laptop, (_) => 0);
    expect(saved, 40000);
    final g = MoneyStats.goal(laptop, saved, now);
    expect(g.done, 0.4);
    expect(g.left, 60000);
    expect(g.perMonth!.round(), closeTo(10000, 200)); // 60000 over about 6 months
    expect(g.onTrack, true); // 40000 in about 3.5 months is over 11000 a month
    expect(MoneyStats.goalSaved({'account': 'Savings'}, (a) => a == 'Savings' ? 25000 : 0), 25000);
    final reached = MoneyStats.goal({'target': 1000}, 1500, now);
    expect(reached.done, 1);
    expect(reached.left, 0);
    expect(reached.onTrack, true);
  });
}
