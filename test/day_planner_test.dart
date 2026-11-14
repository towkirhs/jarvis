import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/day_planner.dart';

final now = DateTime(2026, 11, 5, 9, 2); // Thursday 9:02 am
int at(int h, [int m = 0, int day = 5]) => DateTime(2026, 11, day, h, m).millisecondsSinceEpoch;

Map<String, dynamic> task(int id, String title, {int? est, int priority = 0, int? when, String? cat}) =>
    {'id': id, 'kind': 'task', 'title': title, 'est': est, 'priority': priority, 'when': when, 'cat': cat};

String hm(DateTime d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}';

void main() {
  quickAndHabitTests();
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
      task(4, 'Revise slides', est: 30),
    ];
    List<String> view(DayPlan p) => p.blocks.map((b) => '${hm(b.start)} ${b.title} ${b.minutes}').toList();

    test('a task can be pinned to a time and the others flow around it', () {
      final plan = DayPlanner.plan(now: now, items: items, edits: {3: PlanEdit(start: DateTime(2026, 11, 5, 9, 30))});
      // Read notes (30 min) does not fit in the 25 minutes before 9:30, so it goes after the pinned task.
      expect(view(plan), ['9:30 Lab report 60', '10:30 Read notes 30', '11:10 Revise slides 30']);
    });

    test('a task can get its own length', () {
      final plan = DayPlanner.plan(now: now, items: items, edits: {2: PlanEdit(minutes: 90)});
      expect(view(plan).firstWhere((l) => l.contains('Read notes')), '10:15 Read notes 90');
    });

    test('a task can be left out, and shows up as skipped', () {
      final plan = DayPlanner.plan(now: now, items: items, edits: {4: PlanEdit(skip: true)});
      expect(plan.blocks.any((b) => b.title == 'Revise slides'), false);
      expect(plan.skipped.map((b) => b.title), ['Revise slides']);
    });

    test('a task pinned before the current time keeps that time', () {
      final plan = DayPlanner.plan(now: now, items: items, edits: {2: PlanEdit(start: DateTime(2026, 11, 5, 8))});
      expect(view(plan).first, '8:00 Read notes 30');
    });
  });
}

void quickAndHabitTests() {
  group('quick tasks and habits', () {
    test('calls, payments and short tasks need no block; you can say otherwise', () {
      expect(DayPlanner.isQuick({'title': 'Call Tomalika Apu'}), true);
      expect(DayPlanner.isQuick({'title': 'pay electricity bill'}), true);
      expect(DayPlanner.isQuick({'title': 'Write report', 'est': 5}), true);
      expect(DayPlanner.isQuick({'title': 'Read 200 pages for exam'}), false);
      expect(DayPlanner.isQuick({'title': 'Call plumber', 'quick': false}), false);
      expect(DayPlanner.isQuick({'title': 'Check cBLAST', 'quick': true}), true);
      expect(DayPlanner.isQuick({'title': 'Recall notes'}), false);
    });

    test('quick tasks are listed apart and take no time from the day', () {
      final plan = DayPlanner.plan(now: now, items: [task(1, 'Call Apu'), task(2, 'Read notes', est: 30)]);
      expect(plan.blocks.map((b) => b.title), ['Read notes']);
      expect(plan.quick.map((b) => b.title), ['Call Apu']);
      expect(plan.blocks.first.start, DateTime(2026, 11, 5, 9, 5));
    });

    test('habits due today that take time become tasks to place; done or unscheduled ones do not', () {
      final habits = [
        {'id': 7, 'name': 'Tuition', 'type': 'yesno', 'planMin': 60, 'logs': {}},
        {'id': 8, 'name': 'Study', 'type': 'duration', 'target': 90, 'logs': {}},
        {'id': 9, 'name': 'Walk', 'type': 'duration', 'target': 30, 'logs': {'2026-11-05': {'v': 30}}},
        {'id': 10, 'name': 'Water', 'type': 'quantity', 'target': 3, 'logs': {}},
        {'id': 11, 'name': 'Gym', 'type': 'yesno', 'planMin': 60, 'sched': {'kind': 'days', 'days': [1]}, 'logs': {}},
        {'id': 12, 'name': 'Read', 'type': 'duration', 'target': 20, 'planMin': 0, 'logs': {}},
        {'id': 13, 'name': 'Old', 'type': 'yesno', 'planMin': 30, 'archived': true, 'logs': {}},
      ];
      final t = DayPlanner.habitTasks([for (final h in habits) {...h, 'start': '2026-01-01'}], now);
      expect(t.where((x) => x['quick'] != true).map((x) => '${x['title']} ${x['est']} ${x['id']}'), ['Tuition 60 -7', 'Study 90 -8']);
      expect(t.where((x) => x['quick'] == true).map((x) => x['title']), ['Water', 'Read']);
    });

    test('a habit already on today\'s calendar is not proposed again', () {
      final habits = [
        {'id': 7, 'name': 'Tuition', 'type': 'yesno', 'planMin': 60, 'logs': {}},
      ];
      final items = [
        {'kind': 'event', 'title': 'Tuition', 'when': at(17), 'dur': 60, 'planHabit': 7},
      ];
      expect(DayPlanner.habitTasks([for (final h in habits) {...h, 'start': '2026-01-01'}], now, items: items), isEmpty);
    });
  });
}
