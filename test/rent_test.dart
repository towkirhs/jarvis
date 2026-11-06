import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/rent.dart';

void main() {
  final now = DateTime(2026, 11, 7);
  final room = <String, dynamic>{'id': 1, 'number': '101', 'tenant': 'Rahim', 'rent': 5000, 'advance': 10000, 'start': '2026-09'};
  final bills = <Map<String, dynamic>>[
    {'room': 1, 'month': '2026-10', 'amount': 800},
    {'room': 1, 'month': '2026-11', 'amount': 650},
    {'room': 2, 'month': '2026-11', 'amount': 999}, // another room
  ];
  final pays = <Map<String, dynamic>>[
    {'room': 1, 'month': '2026-09', 'amount': 5000},
    {'room': 1, 'month': '2026-10', 'amount': 5000},
    {'room': 1, 'month': '2026-11', 'amount': 2000},
    {'room': 1, 'month': '2026-11', 'amount': 1000}, // paid in two parts
  ];

  test('months from move-in to now', () {
    expect(Rent.months('2026-09', now), ['2026-09', '2026-10', '2026-11']);
    expect(Rent.months('2025-12', DateTime(2026, 1, 5)), ['2025-12', '2026-01']);
    expect(Rent.name('2026-11'), 'November 2026');
  });

  test('each month: rent plus bill, minus what was paid for it', () {
    expect(Rent.month(room, '2026-09', pays, bills).due, 0);
    expect(Rent.month(room, '2026-10', pays, bills), (rent: 5000, bill: 800, paid: 5000, due: 800));
    expect(Rent.month(room, '2026-11', pays, bills), (rent: 5000, bill: 650, paid: 3000, due: 2650));
  });

  test('total due adds every month; the advance is kept apart', () {
    expect(Rent.totalDue(room, pays, bills, now), 3450);
  });

  test('paying extra one month counts towards another', () {
    final more = [...pays, {'room': 1, 'month': '2026-11', 'amount': 3450}];
    expect(Rent.totalDue(room, more, bills, now), 0);
  });
}
