import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/day_planner.dart';

final now = DateTime(2026, 11, 5, 9, 2); // Thursday 9:02 am
final sat = DateTime(2026, 11, 7);
int at(int h, [int m = 0, int day = 5]) => DateTime(2026, 11, day, h, m).millisecondsSinceEpoch;

Map<String, dynamic> task(int id, String title, {int? est, int? max, int priority = 0, int? when, int? from, int? to}) => {
      'id': id, 'kind': 'task', 'title': title, 'est': est, 'estMax': max, 'priority': priority, 'when': when,
      if (from != null) 'winFrom': from,
      if (to != null) 'winTo': to,
    };

String hm(DateTime d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
List<String> view(DayPlan p) => p.blocks.map((b) => '${hm(b.start)}-${hm(b.end)} ${b.title}').toList();

void main() {
  group('any day', () {
    test('a future day starts at the start of the day, not now', () {
      final p = DayPlanner.plan(now: now, day: sat, items: [task(1, 'Read', est: 60, when: at(9, 0, 7))]);
      expect(view(p), ['8:00-9:00 Read']);
    });

    test('a future day holds the tasks dated that day; undated ones only when added', () {
      final items = [task(1, 'Dated', est: 30, when: at(9, 0, 7)), task(2, 'No date', est: 30), task(3, 'Other day', est: 30, when: at(9, 0, 8))];
      expect(DayPlanner.plan(now: now, day: sat, items: items).blocks.map((b) => b.title), ['Dated']);
      expect(DayPlanner.plan(now: now, day: sat, items: items, extra: {2}).blocks.map((b) => b.title), ['Dated', 'No date']);
    });

    test('a repeating event is fixed on its day', () {
      final p = DayPlanner.plan(now: now, day: sat, items: [
        {'id': 9, 'kind': 'event', 'title': 'Tuition', 'when': at(10, 0, 1), 'dur': 60, 'repeat': 'daily'},
        task(1, 'Read', est: 120, when: at(9, 0, 7)),
      ]);
      expect(view(p), ['8:00-10:00 Read', '10:00-11:00 Tuition']);
    });
  });

  group('windows and ranges', () {
    test('a task stays inside its time window', () {
      final p = DayPlanner.plan(now: now, day: sat, items: [task(1, 'Study', est: 240, when: at(9, 0, 7), from: 13 * 60, to: 20 * 60)]);
      expect(view(p), ['13:00-17:00 Study']);
    });

    test('a window task goes around an event inside its window', () {
      final p = DayPlanner.plan(now: now, day: sat, items: [
        {'id': 9, 'kind': 'event', 'title': 'Class', 'when': at(14, 0, 7), 'dur': 60},
        task(1, 'Study', est: 240, when: at(9, 0, 7), from: 13 * 60, to: 20 * 60),
      ]);
      expect(view(p), ['14:00-15:00 Class', '15:00-19:00 Study']);
    });

    test('a window task is placed before a flexible one that would take its time', () {
      final p = DayPlanner.plan(now: now, day: sat, items: [
        task(1, 'Read', est: 120, priority: 3, when: at(9, 0, 7)),
        task(2, 'Exam prep', est: 240, when: at(9, 0, 7), from: 8 * 60, to: 12 * 60),
      ]);
      expect(view(p), ['8:00-12:00 Exam prep', '12:10-14:10 Read']);
    });

    test('a task that cannot fit its window says why', () {
      final p = DayPlanner.plan(now: now, day: sat, items: [task(1, 'Study', est: 240, when: at(9, 0, 7), from: 13 * 60, to: 15 * 60)]);
      expect(p.blocks, isEmpty);
      expect(p.overflow.single.reason, contains('window'));
    });

    test('a length range takes as much as the free time allows, up to the longest', () {
      final p = DayPlanner.plan(now: now, day: sat, items: [task(1, 'Study', est: 240, max: 270, when: at(9, 0, 7), from: 13 * 60, to: 20 * 60)]);
      expect(view(p), ['13:00-17:30 Study']);
    });

    test('a length range stops before the next block, keeping the break', () {
      final p = DayPlanner.plan(now: now, day: sat, items: [
        {'id': 9, 'kind': 'event', 'title': 'Class', 'when': at(17, 30, 7), 'dur': 30},
        task(1, 'Study', est: 240, max: 300, when: at(9, 0, 7), from: 13 * 60, to: 20 * 60),
      ]);
      expect(view(p), ['13:00-17:20 Study', '17:30-18:00 Class']);
    });

    test('on today, a window that started already begins at the next 5 minutes', () {
      final p = DayPlanner.plan(now: now, items: [task(1, 'Study', est: 60, when: at(9), from: 8 * 60, to: 12 * 60)]);
      expect(view(p), ['9:05-10:05 Study']);
    });
  });

  group('the analysis', () {
    test('says how much time is spare', () {
      final p = DayPlanner.plan(now: now, day: sat, items: [task(1, 'Read', est: 60, when: at(9, 0, 7))]);
      expect(p.notes.join(' '), contains('spare'));
    });

    test('says when the day is short', () {
      final p = DayPlanner.plan(now: now, day: sat, items: [
        task(1, 'A', est: 480, when: at(9, 0, 7)),
        task(2, 'B', est: 480, when: at(9, 0, 7)),
      ]);
      expect(p.notes.join(' '), contains('short'));
      expect(p.overflow.single.reason, isNotEmpty);
    });
  });
}
