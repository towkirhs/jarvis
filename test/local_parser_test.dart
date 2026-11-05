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
}
