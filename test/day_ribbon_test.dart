import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/day_ribbon.dart';

int at(int h, [int m = 0]) => DateTime(2026, 11, 6, h, m).millisecondsSinceEpoch;

void main() {
  final items = <Map<String, dynamic>>[
    {'title': 'Tuition', 'kind': 'event', 'status': 'open', 'when': at(16, 30), 'dur': 90},
    {'title': 'Lab report', 'kind': 'task', 'status': 'open', 'when': at(20), 'est': 60},
    {'title': 'Gym', 'kind': 'task', 'status': 'done', 'when': at(8)},
  ];

  test('free time before the next thing', () {
    expect(DayRibbon.caption(items, DateTime(2026, 11, 6, 14, 10)), '2h 20m free before Tuition at 4:30 pm');
  });

  test('inside something', () {
    expect(DayRibbon.caption(items, DateTime(2026, 11, 6, 17)), 'Now: Tuition, until 6 pm');
  });

  test('done items do not count, and the end of the day is clear', () {
    expect(DayRibbon.caption(items, DateTime(2026, 11, 6, 21, 30)), 'Clear for the rest of the day');
    expect(DayRibbon.caption(items, DateTime(2026, 11, 6, 8, 10)), '8h 20m free before Tuition at 4:30 pm');
  });
}
