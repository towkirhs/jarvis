import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/rent.dart';

int on(int m, int d) => DateTime(2026, m, d).millisecondsSinceEpoch;

void main() {
  final now = DateTime(2026, 11, 7);
  final room = <String, dynamic>{'id': 1, 'number': '1', 'tenant': 'Rahim', 'rent': 5000, 'advance': 10000, 'start': '2026-09', 'opening': 1500};
  final bills = <Map<String, dynamic>>[
    {'room': 1, 'month': '2026-09', 'kind': 'electricity', 'amount': 800},
    {'room': 1, 'month': '2026-09', 'kind': 'wifi', 'amount': 500},
    {'room': 1, 'month': '2026-10', 'kind': 'electricity', 'amount': 650},
    {'room': 1, 'month': '2026-11', 'kind': 'electricity', 'amount': 700}, // charged in December
    {'room': 2, 'month': '2026-10', 'kind': 'electricity', 'amount': 999}, // another room
  ];
  final pays = <Map<String, dynamic>>[
    {'room': 1, 'amount': 6500, 'paidAt': on(9, 5)}, // earlier due + September rent
    {'room': 1, 'amount': 4000, 'paidAt': on(10, 4)}, // short by 2300
    {'room': 1, 'amount': 5000, 'paidAt': on(11, 3)},
  ];

  test("each month adds rent and last month's bills; what is left carries on", () {
    final sep = Rent.month(room, '2026-09', pays, bills);
    expect([sep.carried, sep.charge, sep.paid, sep.left], [1500, 5000, 6500, 0]);
    final oct = Rent.month(room, '2026-10', pays, bills);
    expect([oct.carried, oct.charge, oct.paid, oct.left], [0, 6300, 4000, 2300]);
    expect(oct.bills.map((b) => b['kind']), ['electricity', 'wifi']); // September's bills
    final nov = Rent.month(room, '2026-11', pays, bills);
    expect([nov.carried, nov.charge, nov.paid, nov.left], [2300, 5650, 5000, 2950]);
  });

  test('due now, and the oldest unpaid month', () {
    expect(Rent.due(room, pays, bills, now), 2950);
    // Payments clear the oldest charges first, so November's payment covered October's shortfall.
    expect(Rent.unpaidSince(room, pays, bills, now), '2026-11');
    expect(Rent.unpaidSince(room, pays.take(2).toList(), bills, now), '2026-10'); // no November payment yet
  });

  test('paying it all off, or ahead', () {
    final more = [...pays, {'room': 1, 'amount': 3950, 'paidAt': on(11, 6)}];
    expect(Rent.due(room, more, bills, now), -1000);
    expect(Rent.unpaidSince(room, more, bills, now), isNull);
  });

  test('a payment made before the first month counts in the first month', () {
    final early = [{'room': 1, 'amount': 1500, 'paidAt': on(8, 28)}];
    expect(Rent.month(room, '2026-09', early, const []).left, 5000);
  });

  test('months and names', () {
    expect(Rent.months('2025-12', DateTime(2026, 1, 5)), ['2025-12', '2026-01']);
    expect(Rent.name('2026-11'), 'November 2026');
    expect(Rent.shift('2026-01', -1), '2025-12');
  });
}
