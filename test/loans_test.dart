import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/loans.dart';

void main() {
  Map<String, dynamic> tx(int person, String type, num amount, DateTime at) =>
      {'person': person, 'type': type, 'amount': amount, 'ts': at.millisecondsSinceEpoch};
  final now = DateTime(2026, 11, 11, 14);
  final txs = [
    tx(1, 'gave', 450, DateTime(2026, 10, 19, 22)),
    tx(1, 'took', 30, DateTime(2026, 10, 19, 22)),
    tx(1, 'took', 50, DateTime(2026, 10, 19, 23)),
    tx(2, 'gave', 55, DateTime(2026, 10, 19, 9)),
    tx(2, 'took', 60, DateTime(2026, 10, 19, 21)),
    tx(3, 'took', 200, DateTime(2026, 11, 11, 9)),
  ];

  test('a balance is what I gave minus what I took; positive means they owe me', () {
    expect(Loans.balance(1, txs), 370);
    expect(Loans.balance(2, txs), -5);
    expect(Loans.balance(3, txs), -200);
    expect(Loans.balance(9, txs), 0);
  });

  test('totals split what I will receive from what I must pay, with head counts', () {
    final t = Loans.totals([1, 2, 3], txs);
    expect((t.receive, t.receiveFrom), (370, 1));
    expect((t.pay, t.payTo), (205, 2));
  });

  test('time ranges: today, this week (from Monday), this month', () {
    final today = DateTime(2026, 11, 11, 9).millisecondsSinceEpoch;
    final lastWeek = DateTime(2026, 11, 6).millisecondsSinceEpoch;
    final lastMonth = DateTime(2026, 10, 19).millisecondsSinceEpoch;
    expect([Loans.inRange(today, 'today', now), Loans.inRange(lastWeek, 'today', now)], [true, false]);
    expect([Loans.inRange(today, 'week', now), Loans.inRange(lastWeek, 'week', now)], [true, false]);
    expect([Loans.inRange(lastWeek, 'month', now), Loans.inRange(lastMonth, 'month', now)], [true, false]);
    expect(Loans.inRange(lastMonth, 'all', now), true);
  });
}
