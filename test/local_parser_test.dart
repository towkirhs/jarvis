import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/local_parser.dart';

/// Thursday 5 November 2026, noon.
final now = DateTime(2026, 11, 5, 12);

Map<String, dynamic>? item(String note, {List<String> habits = const [], List<String> accounts = const []}) {
  final r = LocalParser.parse(note, now: now, habits: habits, accounts: accounts);
  return r == null ? null : (r['items'] as List).single as Map<String, dynamic>;
}

void main() {
  group('alarms', () {
    test('alarm at 6 is 6 am', () {
      expect(item('alarm at 6'), allOf(containsPair('type', 'alarm'), containsPair('time', '06:00'), containsPair('title', 'Alarm')));
    });
    test('wake me up tomorrow', () {
      expect(item('wake me up at 6:30 tomorrow'),
          allOf(containsPair('type', 'alarm'), containsPair('time', '06:30'), containsPair('date', '2026-11-06'), containsPair('title', 'Wake up')));
    });
  });

  group('finishing things', () {
    test('finished the lab report', () {
      expect(item('Finished the lab report'), allOf(containsPair('type', 'complete'), containsPair('target', 'lab report')));
    });
    test("I've done my assignment", () {
      expect(item("I've done my assignment"), allOf(containsPair('type', 'complete'), containsPair('target', 'assignment')));
    });
    test('a tracked habit is a habit log, not a task', () {
      expect(item('did gym today', habits: ['Gym']), containsPair('type', 'habit_log'));
    });
  });

  group('tasks and events', () {
    test('Banglish class tomorrow', () {
      expect(item('kal 4.30 e tuition ase'),
          allOf(containsPair('type', 'event'), containsPair('title', 'Tuition'), containsPair('date', '2026-11-06'), containsPair('time', '16:30')));
    });
    test('task with a time only', () {
      expect(item('Call Ammu at 9 pm'),
          allOf(containsPair('type', 'task'), containsPair('title', 'Call Ammu'), containsPair('time', '21:00'), containsPair('date', null)));
    });
    test('event on a weekday', () {
      expect(item('meeting with supervisor friday 3pm'),
          allOf(containsPair('type', 'event'), containsPair('title', 'Meeting with supervisor'), containsPair('date', '2026-11-06'), containsPair('time', '15:00')));
    });
    test('deadline', () {
      expect(item('submit lab report by 5pm'), allOf(containsPair('title', 'Submit lab report'), containsPair('time', '17:00')));
    });
    test('date without a time is all day', () {
      expect(item('buy groceries tomorrow'),
          allOf(containsPair('type', 'task'), containsPair('title', 'Buy groceries'), containsPair('date', '2026-11-06'), containsPair('time', null)));
    });
    test('exam on a date', () {
      expect(item('exam on 20 december'), allOf(containsPair('type', 'event'), containsPair('title', 'Exam'), containsPair('date', '2026-12-20')));
    });
    test('moving an item', () {
      expect(item('move dentist to friday 5pm'),
          allOf(containsPair('type', 'delay'), containsPair('target', 'dentist'), containsPair('date', '2026-11-06'), containsPair('time', '17:00')));
    });
  });

  group('money', () {
    const accounts = ['Cash', 'Bank', 'bKash'];
    test('expense with an account', () {
      expect(item('spent 250 on lunch with bKash', accounts: accounts),
          allOf(containsPair('type', 'money'), containsPair('moneyType', 'expense'), containsPair('amount', 250), containsPair('category', 'Food'),
              containsPair('title', 'Lunch'), containsPair('account', 'bKash')));
    });
    test('income', () {
      expect(item('got 5000 tuition fee', accounts: accounts),
          allOf(containsPair('moneyType', 'income'), containsPair('amount', 5000), containsPair('category', 'Tuition')));
    });
    test('1.2k', () {
      expect(item('spent 1.2k on shoes'), allOf(containsPair('amount', 1200.0), containsPair('category', 'Shopping'), containsPair('title', 'Shoes')));
    });
    test('a time is not an amount', () {
      expect(item('spent 250 on lunch at 2pm'), allOf(containsPair('amount', 250), containsPair('category', 'Food')));
    });
  });

  group('habits and birthdays', () {
    const habits = ['Gym', 'Reading'];
    test('did a habit', () {
      expect(item('went to the gym', habits: habits),
          allOf(containsPair('type', 'habit_log'), containsPair('habit', 'Gym'), containsPair('done', true), containsPair('date', '2026-11-05')));
    });
    test('skipped a habit', () {
      expect(item('skipped reading today', habits: habits), allOf(containsPair('habit', 'Reading'), containsPair('done', false)));
    });
    test('birthday next year', () {
      expect(item("Rafi's birthday is 12 March"),
          allOf(containsPair('type', 'countdown'), containsPair('category', 'birthday'), containsPair('title', "Rafi's birthday"), containsPair('date', '2027-03-12')));
    });
  });

  group('left to the AI', () {
    for (final note in [
      'I woke up at 7 today feeling great',
      'Today was a long day. I finished the gel run.',
      'call mom at 5 and gym at 7',
      'buy 3 eggs',
      'got a call at 5',
      'business meeting went well',
    ]) {
      test(note, () => expect(LocalParser.parse(note, now: now), isNull));
    }
  });

  group('calendar: start, end, name', () {
    Map<String, dynamic>? cal(String note) {
      final r = LocalParser.calendar(note, now: now);
      return r == null ? null : (r['items'] as List).single as Map<String, dynamic>;
    }

    Matcher ev(String title, String date, String time, int? minutes) => allOf(containsPair('type', 'event'),
        containsPair('title', title), containsPair('date', date), containsPair('time', time), containsPair('durationMinutes', minutes));

    test('start and end times', () {
      expect(cal('3pm to 5pm team meeting'), ev('Team meeting', '2026-11-05', '15:00', 120));
      expect(cal('3 5 pm football'), ev('Football', '2026-11-05', '15:00', 120));
      expect(cal('10:30-12 dentist'), ev('Dentist', '2026-11-05', '10:30', 90));
      expect(cal('11 to 1 pm lunch with Rafi'), ev('Lunch with Rafi', '2026-11-05', '11:00', 120));
      expect(cal('from 2:15 pm until 3 pm call with bank'), ev('Call with bank', '2026-11-05', '14:15', 45));
      expect(cal('8 - 10 pm movie'), ev('Movie', '2026-11-05', '20:00', 120));
    });
    test('with a day', () {
      expect(cal('tomorrow 9am to 11am physics class'), ev('Physics class', '2026-11-06', '09:00', 120));
      expect(cal('dec 12 3 to 5pm exam'), ev('Exam', '2026-12-12', '15:00', 120));
      expect(cal('3pm 4pm meeting with supervisor on friday'), ev('Meeting with supervisor', '2026-11-06', '15:00', 60));
    });
    test('only a start time', () {
      expect(cal('9am standup'), ev('Standup', '2026-11-05', '09:00', null));
    });
    test('no time or no name: left to the AI', () {
      expect(cal('team meeting'), isNull);
      expect(cal('3pm to 5pm'), isNull);
    });
  });

  group('questions are not turned into tasks', () {
    test('questions go to Jarvis', () {
      expect(item('today any match?'), isNull);
      expect(item('Today any match'), isNull);
      expect(item('what is on tomorrow at 5'), isNull);
      expect(item('is dinner at 8 tonight'), isNull);
      expect(item('meeting tomorrow at 3pm?'), isNull);
      expect(LocalParser.isQuestion('Hey Jarvis, when is my exam'), isTrue);
    });
    test('plain plans still are', () {
      expect(item('call Ammu tomorrow at 8 pm'), allOf(containsPair('type', 'task'), containsPair('time', '20:00')));
      expect(LocalParser.isQuestion('do laundry tomorrow'), isFalse);
      expect(LocalParser.isQuestion('anything in the fridge to buy'), isFalse);
    });
  });
}
