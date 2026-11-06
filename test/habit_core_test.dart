import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/habit_core.dart';

final now = DateTime(2026, 11, 7, 20); // Saturday evening
DateTime day(int d, [int m = 11]) => DateTime(2026, m, d);
String k(int d, [int m = 11]) => dk(day(d, m));

Map<String, dynamic> habit(Map<String, dynamic> logs, {Map<String, dynamic> extra = const {}}) =>
    {'id': 1, 'name': 'X', 'start': '2026-11-01', 'sched': {'kind': 'daily'}, 'logs': logs, ...extra};

void main() {
  group('old habits keep working', () {
    test('3 times a week, yes/no logs', () {
      final h = {'id': 1, 'name': 'Gym', 'times': 3, 'per': 'week', 'logs': {k(2): 'yes', k(4): 'yes', k(6): 'yes', k(3): 'no'}};
      expect(HabitCore.describe(h), '3 times a week');
      expect(HabitCore.periodCount(h, HabitCore.periodStart(h, now)), 3);
      expect(HabitCore.dueToday(h, now), isFalse); // target reached this week
      expect(HabitCore.currentStreak(h, now), 1);
      expect(HabitCore.unit(h), 'week');
    });
    test('7 a week is every day', () {
      expect(HabitCore.describe({'times': 7, 'per': 'week', 'logs': {}}), 'Every day');
    });
  });

  group('measuring a day', () {
    test('count, quantity and distance reach their target', () {
      final h = habit({k(7): {'v': 15}}, extra: {'type': 'count', 'target': 20});
      expect(HabitCore.progress(h, day(7)), 0.75);
      expect(HabitCore.done(h, day(7)), isFalse);
      (h['logs'] as Map)[k(7)] = {'v': 22};
      expect(HabitCore.done(h, day(7)), isTrue);
    });
    test('limit: under the maximum is done, over is not', () {
      final h = habit({k(6): {'v': 90}, k(7): {'v': 150}}, extra: {'type': 'limit', 'target': 120});
      expect(HabitCore.done(h, day(6)), isTrue);
      expect(HabitCore.done(h, day(7)), isFalse);
    });
    test('by a time', () {
      final h = habit({k(6): {'at': '05:50'}, k(7): {'at': '06:20'}}, extra: {'type': 'time', 'by': '06:00'});
      expect(HabitCore.done(h, day(6)), isTrue);
      expect(HabitCore.done(h, day(7)), isFalse);
    });
    test('checklist', () {
      final h = habit({k(7): {'items': [true, false, true, true]}}, extra: {'type': 'checklist', 'items': ['a', 'b', 'c', 'd']});
      expect(HabitCore.progress(h, day(7)), 0.75);
    });
    test('rating at or above the good mark', () {
      final h = habit({k(6): {'v': 8}, k(7): {'v': 5}}, extra: {'type': 'rating', 'scale': 10, 'target': 7});
      expect(HabitCore.done(h, day(6)), isTrue);
      expect(HabitCore.done(h, day(7)), isFalse);
    });
  });

  group('targets over time', () {
    test('an old day keeps the target it had', () {
      final h = habit({k(2): {'v': 20}, k(6): {'v': 20}},
          extra: {'type': 'count', 'target': 20, 'targets': [{'from': '2026-11-05', 'v': 30}]});
      expect(HabitCore.done(h, day(2)), isTrue);
      expect(HabitCore.done(h, day(6)), isFalse);
    });
    test('progressive: +5 a week up to 40', () {
      final h = habit({}, extra: {'type': 'count', 'target': 20, 'prog': {'by': 5, 'every': 7, 'max': 40}});
      expect(HabitCore.target(h, day(1)), 20);
      expect(HabitCore.target(h, day(8)), 25);
      expect(HabitCore.target(h, day(29)), 40);
    });
  });

  group('schedules', () {
    test('chosen weekdays', () {
      final h = habit({}, extra: {'sched': {'kind': 'days', 'days': [1, 3, 5]}});
      expect([for (var d = 2; d <= 8; d++) HabitCore.scheduled(h, day(d))], [true, false, true, false, true, false, false]);
      expect(HabitCore.describe(h), 'Mon, Wed, Fri');
    });
    test('every 3 days from the start', () {
      final h = habit({}, extra: {'sched': {'kind': 'every', 'n': 3}});
      expect([for (var d = 1; d <= 7; d++) HabitCore.scheduled(h, day(d))], [true, false, false, true, false, false, true]);
    });
    test('once', () {
      final h = habit({}, extra: {'sched': {'kind': 'once', 'date': '2026-11-05'}});
      expect(HabitCore.scheduled(h, day(5)), isTrue);
      expect(HabitCore.scheduled(h, day(6)), isFalse);
    });
    test('paused days are not scheduled and do not break streaks', () {
      final h = habit({k(1): 'yes', k(2): 'yes', k(6): 'yes'}, extra: {'off': [['2026-11-03', '2026-11-05']]});
      expect(HabitCore.scheduled(h, day(4)), isFalse);
      expect(HabitCore.currentStreak(h, now), 3); // 1, 2, (paused 3-5), 6; today pending
    });
  });

  group('streaks', () {
    test('today not done yet does not break it; rest days pass', () {
      final h = habit({k(3): 'yes', k(4): 'skip', k(5): 'yes', k(6): 'yes'});
      expect(HabitCore.currentStreak(h, now), 3);
      expect(HabitCore.missedCount(h, now), 2); // 1 and 2
    });
    test('a miss ends it, unless grace allows one', () {
      final logs = {k(1): 'yes', k(2): 'yes', k(3): 'yes', k(5): 'yes', k(6): 'yes', k(7): 'yes'};
      expect(HabitCore.currentStreak(habit(logs), now), 3);
      expect(HabitCore.currentStreak(habit(logs, extra: {'grace': 1}), now), 6);
      expect(HabitCore.longestStreak(habit(logs), now), 3);
      expect(HabitCore.longestStreak(habit(logs, extra: {'grace': 1}), now), 6);
    });
    test('consistency leaves out rest days and today in progress', () {
      final h = habit({k(1): 'yes', k(2): 'yes', k(3): 'no', k(4): 'skip', k(5): 'yes', k(6): 'yes'});
      expect(HabitCore.consistency(h, now), 80); // 4 of 5
    });
  });

  group('today', () {
    test('due, then off the due list once done or skipped', () {
      final h = habit({});
      expect(HabitCore.dueToday(h, now), isTrue);
      (h['logs'] as Map)[k(7)] = 'skip';
      expect(HabitCore.dueToday(h, now), isFalse);
      expect(HabitCore.onToday(h, now), isTrue);
    });
    test("day progress averages today's habits", () {
      final a = habit({k(7): 'yes'});
      final b = habit({k(7): {'v': 1}}, extra: {'id': 2, 'type': 'quantity', 'target': 2});
      expect(HabitCore.dayProgress([a, b], now), 0.75);
    });
    test('stacking: the next habit after one just done', () {
      final a = habit({k(7): 'yes'});
      final b = habit({}, extra: {'id': 2, 'after': 1});
      expect(HabitCore.nextInStack([a, b], a, now)?['id'], 2);
    });
    test('milestones', () {
      final h = habit({for (var d = 1; d <= 7; d++) k(d): 'yes'});
      final (reached, next) = HabitCore.milestonesOf(h);
      expect(reached, [1, 7]);
      expect(next, 21);
    });
  });
}
