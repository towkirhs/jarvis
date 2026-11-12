import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/day_planner.dart';

final now = DateTime(2026, 11, 5, 9, 2); // Thursday 9:02 am
int at(int h, [int m = 0, int day = 5]) => DateTime(2026, 11, day, h, m).millisecondsSinceEpoch;

Map<String, dynamic> task(int id, String title, {int? est, int priority = 0, int? when, String? cat}) =>
    {'id': id, 'kind': 'task', 'title': title, 'est': est, 'priority': priority, 'when': when, 'cat': cat};

String hm(DateTime d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}';

void main() {
  editTests();
  test('fills the morning around a fixed class, most urgent first', () {
    final plan = DayPlanner.plan(now: now, items: [
      {'id': 1, 'kind': 'event', 'title': 'Class', 'when': at(11), 'dur': 60},
      task(2, 'Read notes', est: 30),
      task(3, 'Lab report', est: 60, priority: 3),
    ]);
    expect(plan.blocks.map((b) => '${hm(b.start)} ${b.title}').toList(), [
      '9:05 Lab report', // high priority first, at the next 5 minutes
      '10:15 Read notes', // after a 10 minute break
      '11:00 Class',
    ]);
    expect(plan.overflow, isEmpty);
  });

  test('a task too long for the gap before a class goes after it', () {
    final plan = DayPlanner.plan(now: now, items: [
      {'id': 1, 'kind': 'event', 'title': 'Class', 'when': at(10), 'dur': 90},
      task(2, 'Write essay', est: 120),
    ]);
    expect(plan.blocks.map((b) => '${hm(b.start)} ${b.title}').toList(), ['10:00 Class', '11:30 Write essay']);
  });

  test('overdue tasks come first; future tasks are left alone', () {
    final plan = DayPlanner.plan(now: now, items: [
      task(1, 'Later this week', est: 30, when: at(9, 0, 7)),
      task(2, 'No date', est: 30, priority: 3),
      task(3, 'Was due yesterday', est: 30, when: at(17, 0, 4)),
    ]);
    expect(plan.blocks.map((b) => b.title).toList(), ['Was due yesterday', 'No date']);
  });

  test('learned estimates make tasks longer', () {
    final plan = DayPlanner.plan(now: now, items: [task(1, 'Report', est: 60, cat: 'report')], ratios: {'report': 1.5});
    expect(plan.blocks.single.minutes, 90);
  });

  test("what doesn't fit is listed", () {
    final late = DateTime(2026, 11, 5, 21, 0);
    final plan = DayPlanner.plan(now: late, items: [task(1, 'Short', est: 30), task(2, 'Long', est: 120)]);
    expect(plan.blocks.map((b) => b.title).toList(), ['Short']);
    expect(plan.overflow.map((b) => b.title).toList(), ['Long']);
  });
}

void editTests() {
  group('edits to the proposed plan', () {
    final items = [
      task(2, 'Read notes', est: 30),
      task(3, 'Lab report', est: 60, priority: 3),
      task(4, 'Call Apu', est: 30),
    ];
    List<String> view(DayPlan p) => p.blocks.map((b) => '${hm(b.start)} ${b.title} ${b.minutes}').toList();

    test('a task can be pinned to a time and the others flow around it', () {
      final plan = DayPlanner.plan(now: now, items: items, edits: {3: PlanEdit(start: DateTime(2026, 11, 5, 9, 30))});
      // Read notes (30 min) does not fit in the 25 minutes before 9:30, so it goes after the pinned task.
      expect(view(plan), ['9:30 Lab report 60', '10:30 Read notes 30', '11:10 Call Apu 30']);
    });

    test('a task can get its own length', () {
      final plan = DayPlanner.plan(now: now, items: items, edits: {2: PlanEdit(minutes: 90)});
      expect(view(plan).firstWhere((l) => l.contains('Read notes')), '10:15 Read notes 90');
    });

    test('a task can be left out, and shows up as skipped', () {
      final plan = DayPlanner.plan(now: now, items: items, edits: {4: PlanEdit(skip: true)});
      expect(plan.blocks.any((b) => b.title == 'Call Apu'), false);
      expect(plan.skipped.map((b) => b.title), ['Call Apu']);
    });

    test('a task pinned before the current time keeps that time', () {
      final plan = DayPlanner.plan(now: now, items: items, edits: {2: PlanEdit(start: DateTime(2026, 11, 5, 8))});
      expect(view(plan).first, '8:00 Read notes 30');
    });
  });
}
