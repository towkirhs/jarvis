import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/habit_link.dart';

void main() {
  blockTests();
  final now = DateTime(2026, 11, 12, 15);
  int at(int d, int h, [int m = 0]) => DateTime(2026, 11, d, h, m).millisecondsSinceEpoch;
  Map<String, dynamic> event(String title, int when, int dur) => {'kind': 'event', 'title': title, 'when': when, 'dur': dur, 'status': 'open'};

  test('words match whole words, any case', () {
    expect(HabitLink.matches('Tuition with Rafi', ['tuition']), true);
    expect(HabitLink.matches('SLEEP', ['sleep']), true);
    expect(HabitLink.matches('Sleepover', ['sleep']), false);
    expect(HabitLink.matches('Tuition', []), false);
  });

  test('a finished tuition event marks a yes/no habit done that day; one still going does not', () {
    final h = {'type': 'yesno', 'link': ['tuition']};
    final r = HabitLink.compute(h, [event('Tuition', at(11, 17), 60), event('Tuition', at(12, 14, 30), 60)], now);
    expect(r, {'2026-11-11': {'v': 1, 'cal': true}});
  });

  test('a duration habit gets the minutes, added up across events', () {
    final h = {'type': 'duration', 'target': 120, 'link': ['tuition']};
    final r = HabitLink.compute(h, [event('Tuition A', at(11, 9), 60), event('tuition B', at(11, 13), 90)], now);
    expect(r['2026-11-11'], {'v': 150, 'cal': true});
  });

  test('sleep from 2 am to 6 am gives 240 minutes; sleep across midnight counts for the waking day', () {
    final h = {'type': 'duration', 'target': 420, 'link': ['sleep']};
    expect(HabitLink.compute(h, [event('Sleep', at(12, 2), 240)], now)['2026-11-12'], {'v': 240, 'cal': true});
    expect(HabitLink.compute(h, [event('Sleep', at(10, 23), 420)], now).keys, ['2026-11-11']);
  });

  test('a "be up by" habit takes the time the sleep ended', () {
    final h = {'type': 'time', 'by': '07:00', 'link': ['sleep']};
    expect(HabitLink.compute(h, [event('sleep', at(12, 0, 30), 375)], now)['2026-11-12'], {'at': '06:45', 'cal': true});
  });

  test('a count habit counts events; a finished task counts on the day it was done', () {
    final h = {'type': 'count', 'target': 2, 'link': ['call']};
    final r = HabitLink.compute(h, [
      event('Call mum', at(11, 10), 15),
      {'kind': 'task', 'title': 'Call Apu', 'status': 'done', 'doneAt': at(11, 20)},
      {'kind': 'task', 'title': 'Call bank', 'status': 'open', 'when': at(11, 9)},
    ], now);
    expect(r['2026-11-11'], {'v': 2, 'cal': true});
  });

  test('cancelled events and events older than two weeks are ignored', () {
    final h = {'type': 'yesno', 'link': ['gym']};
    final r = HabitLink.compute(h, [
      {...event('Gym', at(11, 7), 60), 'status': 'cancelled'},
      event('Gym', DateTime(2026, 10, 20, 7).millisecondsSinceEpoch, 60),
    ], now);
    expect(r, isEmpty);
  });

  test('applying keeps what you logged yourself and clears calendar logs whose event is gone', () {
    final logs = <String, dynamic>{
      '2026-11-10': 'yes',
      '2026-11-09': {'v': 1, 'cal': true},
      '2026-11-08': {'v': 1, 'cal': true},
    };
    final changed = HabitLink.apply(logs, {'2026-11-10': {'v': 1, 'cal': true}, '2026-11-09': {'v': 1, 'cal': true}, '2026-11-11': {'v': 1, 'cal': true}}, now);
    expect(changed, true);
    expect(logs, {'2026-11-10': 'yes', '2026-11-09': {'v': 1, 'cal': true}, '2026-11-11': {'v': 1, 'cal': true}});
    expect(HabitLink.apply(logs, {'2026-11-09': {'v': 1, 'cal': true}, '2026-11-11': {'v': 1, 'cal': true}}, now), false);
  });
}

void blockTests() {
  final now = DateTime(2026, 11, 12, 15, 0);
  group('a ticked habit becomes a calendar block', () {
    test('ticked today: a 30 minute block ending now', () {
      final b = HabitLink.block({'type': 'yesno'}, '2026-11-12', {'v': 1}, now)!;
      expect((b.start, b.minutes), (DateTime(2026, 11, 12, 14, 30), 30));
    });

    test('a duration habit uses the logged minutes', () {
      final b = HabitLink.block({'type': 'duration', 'target': 60}, '2026-11-12', {'v': 90}, now)!;
      expect((b.start, b.minutes), (DateTime(2026, 11, 12, 13, 30), 90));
    });

    test('a "by a time" habit ends at the time you logged', () {
      final b = HabitLink.block({'type': 'time', 'by': '07:00'}, '2026-11-12', {'at': '06:40'}, now)!;
      expect(b.start, DateTime(2026, 11, 12, 6, 10));
    });

    test('a past day is placed in the evening', () {
      final b = HabitLink.block({'type': 'yesno'}, '2026-11-10', {'v': 1}, now)!;
      expect(b.start, DateTime(2026, 11, 10, 20));
    });

    test('nothing for a miss, a rest day, a calendar log, or a limit habit', () {
      expect(HabitLink.block({'type': 'yesno'}, '2026-11-12', {'miss': true}, now), isNull);
      expect(HabitLink.block({'type': 'yesno'}, '2026-11-12', 'skip', now), isNull);
      expect(HabitLink.block({'type': 'yesno'}, '2026-11-12', {'v': 1, 'cal': true}, now), isNull);
      expect(HabitLink.block({'type': 'limit', 'target': 120}, '2026-11-12', {'v': 30}, now), isNull);
    });

    test('blocks made from a habit never count back into that habit', () {
      final h = {'id': 7, 'type': 'yesno', 'link': ['gym']};
      final items = [
        {'kind': 'event', 'title': 'Gym', 'when': DateTime(2026, 11, 11, 7).millisecondsSinceEpoch, 'dur': 60, 'status': 'open', 'habitId': 7},
      ];
      expect(HabitLink.compute(h, items, now), isEmpty);
    });
  });
}
