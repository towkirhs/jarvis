import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/income.dart';
import 'package:jarcis/rent.dart';

void main() {
  final now = DateTime(2026, 11, 16);

  test('a salary is owed for months that have ended, less what was paid', () {
    final tuition = {'id': 1, 'name': 'Tuition', 'amount': 3000, 'start': '2026-09'};
    expect(Income.monthsEnded(tuition, now), 2); // September and October
    expect(Income.due(tuition, const [], now), 6000);
    expect(Income.due(tuition, [{'source': 1, 'amount': 3000}, {'source': 2, 'amount': 999}], now), 3000);
    expect(Income.due(tuition, [{'source': 1, 'amount': 9000}], now), -3000); // November paid ahead
  });

  test('a job that ended stops adding up and is no longer monthly income', () {
    final old = {'id': 2, 'name': 'Shop', 'amount': 8000, 'start': '2026-06', 'end': '2026-08'};
    final job = {'id': 3, 'name': 'Office', 'amount': 20000, 'start': '2026-11'};
    expect(Income.monthsEnded(old, now), 3);
    expect(Income.active(old, now), false);
    expect(Income.monthsEnded(job, now), 0);
    expect(Income.monthly([old, job], now), 20000);
  });

  test('a metered bill is the units used times the price of one, and the next one starts from the last reading', () {
    expect(Rent.meter(200, 210, 10), 100);
    expect(Rent.meter(210, 200, 10), 0);
    final bills = [
      {'room': 1, 'month': '2026-09', 'kind': 'electricity', 'amount': 100, 'from': 200, 'to': 210, 'rate': 10},
      {'room': 1, 'month': '2026-10', 'kind': 'electricity', 'amount': 150, 'from': 210, 'to': 225, 'rate': 10},
      {'room': 2, 'month': '2026-10', 'kind': 'electricity', 'amount': 50, 'from': 5, 'to': 10, 'rate': 10},
    ];
    expect(Rent.lastReading(1, 'electricity', '2026-11', bills), 225);
    expect(Rent.lastReading(1, 'electricity', '2026-10', bills), 210);
    expect(Rent.lastReading(1, 'water', '2026-11', bills), isNull);
  });

  test('dues through last month leave this month out but count every payment', () {
    final room = {'id': 1, 'number': '1', 'rent': 5000, 'start': '2026-09', 'opening': 0};
    final bills = [{'room': 1, 'month': '2026-10', 'kind': 'electricity', 'amount': 200}]; // charged in November
    final pays = [
      {'room': 1, 'amount': 5000, 'paidAt': DateTime(2026, 10, 5).millisecondsSinceEpoch},
      {'room': 1, 'amount': 2000, 'paidAt': DateTime(2026, 11, 3).millisecondsSinceEpoch},
    ];
    expect(Rent.due(room, pays, bills, now), 15200 - 7000);
    expect(Rent.dueThrough(room, pays, bills, now, '2026-11'), 8200);
    expect(Rent.dueThrough(room, pays, bills, now, '2026-10'), 3000); // September and October rent, less 7000
    expect(Rent.dueThrough(room, pays, bills, now, '2026-09'), -2000);
  });
}
