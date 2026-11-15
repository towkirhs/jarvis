import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/cal_index.dart';
import 'package:jarcis/day_planner.dart';
import 'package:jarcis/store.dart';

int at(int d, int h, [int m = 0]) => DateTime(2026, 11, d, h, m).millisecondsSinceEpoch;
Map<String, dynamic> ev(int id, String title, int when, {String? repeat, bool allDay = false}) =>
    {'id': id, 'kind': 'event', 'title': title, 'when': when, 'dur': 60, 'repeat': repeat, 'allDay': allDay};

void main() {
  const shift = 5 * 60;

  group('a day from 5 am to 4:59 am', () {
    final items = [
      ev(1, 'Late study', at(16, 1, 30)), // 1:30 am on the 16th
      ev(2, 'Morning class', at(16, 9)),
      ev(3, 'Just before five', at(16, 4, 59)),
      ev(4, 'Exam day', at(16, 9), allDay: true),
    ];

    test('off: midnight splits the days as usual', () {
      final idx = CalIndex.build(items, DateTime(2026, 11, 15), DateTime(2026, 11, 16));
      expect(idx['2026-11-15'], isNull);
      expect(idx['2026-11-16']!.map((e) => e.item['title']), ['Exam day', 'Late study', 'Just before five', 'Morning class']);
    });

    test('on: the night after midnight belongs to the day before; all-day items keep their date', () {
      final idx = CalIndex.build(items, DateTime(2026, 11, 15), DateTime(2026, 11, 16), shift: shift);
      expect(idx['2026-11-15']!.map((e) => e.item['title']), ['Late study', 'Just before five']);
      expect(idx['2026-11-16']!.map((e) => e.item['title']), ['Exam day', 'Morning class']);
    });

    test('on: a daily repeat at 1 am shows once per day, at the end of each day', () {
      final idx = CalIndex.build([ev(5, 'Night walk', at(10, 1), repeat: 'daily')], DateTime(2026, 11, 15), DateTime(2026, 11, 16), shift: shift);
      expect(idx['2026-11-15']!.single.start, DateTime(2026, 11, 16, 1));
      expect(idx['2026-11-16']!.single.start, DateTime(2026, 11, 17, 1));
    });

    test('which day a moment belongs to', () {
      expect(dayKey(CalIndex.dayOf(DateTime(2026, 11, 16, 2), shift)), '2026-11-15');
      expect(dayKey(CalIndex.dayOf(DateTime(2026, 11, 16, 5), shift)), '2026-11-16');
      expect(dayKey(CalIndex.dayOf(DateTime(2026, 11, 16, 2), 0)), '2026-11-16');
    });
  });

  group('Plan my day with the day starting at 5 am', () {
    Map<String, dynamic> task(int id, String title, int est, int when) =>
        {'id': id, 'kind': 'task', 'title': title, 'est': est, 'priority': 0, 'when': when, 'allDay': false};

    test('at 1 am the day being planned is still yesterday, with time until 5 am', () {
      final now = DateTime(2026, 11, 16, 1, 2);
      final p = DayPlanner.plan(now: now, dayShift: shift, items: [task(1, 'Finish essay', 60, at(15, 20))]);
      expect(p.blocks.single.start, DateTime(2026, 11, 16, 1, 5));
      expect(p.overflow, isEmpty);
    });

    test('a task dated 2 am on the 16th belongs to the 15th', () {
      final now = DateTime(2026, 11, 14, 10);
      final items = [task(1, 'Night task', 30, at(16, 2))];
      expect(DayPlanner.plan(now: now, day: DateTime(2026, 11, 15), dayShift: shift, items: items).blocks.single.title, 'Night task');
      expect(DayPlanner.plan(now: now, day: DateTime(2026, 11, 16), dayShift: shift, items: items).blocks, isEmpty);
      // Off: it is the 16th's.
      expect(DayPlanner.plan(now: now, day: DateTime(2026, 11, 16), items: items).blocks.single.title, 'Night task');
    });

    test('an event after midnight is a fixed block of the day before', () {
      final now = DateTime(2026, 11, 14, 10);
      final p = DayPlanner.plan(now: now, day: DateTime(2026, 11, 15), dayShift: shift, items: [ev(1, 'Late call', at(16, 0, 30))]);
      expect(p.blocks.single.fixed, true);
    });
  });
}
