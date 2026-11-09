import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/quick_answers.dart';

final now = DateTime(2026, 11, 6, 18, 0); // Friday 6 pm
int at(int day, int h, [int m = 0]) => DateTime(2026, 11, day, h, m).millisecondsSinceEpoch;

final items = <Map<String, dynamic>>[
  {'title': 'Pay electricity bill', 'status': 'open', 'when': at(5, 10)},
  {'title': 'Buy groceries', 'status': 'open', 'when': at(6, 19)},
  {'title': 'Call Ammu', 'status': 'open', 'when': at(6, 21)},
  {'title': 'Tuition class', 'status': 'open', 'when': at(6, 16, 30)}, // already past
  {'title': 'Gym', 'status': 'open', 'when': at(7, 7)},
  {'title': 'Exam prep', 'status': 'open', 'when': at(7, 0), 'allDay': true},
  {'title': 'Done thing', 'status': 'done', 'when': at(7, 9)},
];
final tx = <Map<String, dynamic>>[
  {'type': 'expense', 'amount': 250, 'cat': 'Food', 'ts': at(6, 13)},
  {'type': 'expense', 'amount': 60, 'cat': 'Transport', 'ts': at(6, 9)},
  {'type': 'expense', 'amount': 500, 'cat': 'Food', 'ts': at(3, 20)},
  {'type': 'expense', 'amount': 1200, 'cat': 'Bills', 'ts': at(1, 10)}, // last week, this month
  {'type': 'income', 'amount': 5000, 'cat': 'Tuition', 'ts': at(6, 10)},
  {'type': 'expense', 'amount': 40, 'cat': null, 'ts': at(6, 8)}, // old record without a category
];

String? ask(String q) => QuickAnswers.answer(q,
    now: now, items: items, tx: tx, balances: {'Cash': 250, 'bKash': 5940}, money: (v) => '৳$v');

void main() {
  test("today's plan lists what is still ahead and counts overdue", () {
    expect(ask("What's on today?"), '2 for today: Buy groceries at 7:00 pm, Call Ammu at 9:00 pm. Also 2 overdue.');
  });

  test("tomorrow's plan, all-day items without a time", () {
    expect(ask('what do I have tomorrow'), '2 for tomorrow: Exam prep, Gym at 7:00 am.');
  });

  test('spending by period, with the biggest categories', () {
    expect(ask('How much did I spend today?'), 'You spent ৳350 today. Most on Food ৳250, Transport ৳60, Other ৳40.');
    expect(ask('how much did I spend this week'), 'You spent ৳850 this week. Most on Food ৳750, Transport ৳60, Other ৳40.');
    expect(ask('how much have I spent'), 'You spent ৳2050 this month. Most on Bills ৳1200, Food ৳750, Transport ৳60.');
  });

  test('spending on one category', () {
    expect(ask('how much did i spend on food this week?'), 'You spent ৳750 on Food this week.');
  });

  test('balance', () {
    expect(ask("what's my balance"), 'You have ৳6190 in total: Cash ৳250, bKash ৳5940.');
  });

  test('balance of one account', () {
    expect(ask('how much cash do I have'), 'You have ৳250 in Cash.');
    expect(ask("what's my bKash balance?"), 'You have ৳5940 in bKash.');
  });

  test('what is next', () {
    expect(ask("what's my next event?"), 'Next up: Buy groceries at 7:00 pm today.');
    expect(ask("what's next"), 'Next up: Buy groceries at 7:00 pm today.');
    String? later(DateTime t, String q) => QuickAnswers.answer(q,
        now: t, items: items, tx: tx, balances: {'Cash': 250}, money: (v) => '৳$v');
    expect(later(DateTime(2026, 11, 6, 22), 'when is my next task'), 'Next up: Exam prep, all day tomorrow.');
    expect(later(DateTime(2026, 11, 7, 10), "what's next"), 'Nothing coming up.');
  });

  test('overdue', () {
    expect(ask('anything overdue?'), '2 overdue: Pay electricity bill, Tuition class.');
    expect(
      QuickAnswers.answer("what's overdue", now: DateTime(2026, 11, 5, 8), items: items, tx: tx, balances: {}, money: (v) => '$v'),
      'Nothing overdue.',
    );
  });

  test('good morning gives the briefing', () {
    const plan = '2 for today: Buy groceries at 7:00 pm, Call Ammu at 9:00 pm. Also 2 overdue.';
    expect(ask('Good morning'), 'Good morning. Friday 6 November. $plan');
    expect(ask('Hey Jarvis, good morning'), 'Good morning. Friday 6 November. $plan');
    expect(ask('brief me'), 'Good evening. Friday 6 November. $plan'); // it is 6 pm in the test
  });

  test('other notes are left alone', () {
    expect(ask('Buy groceries today at 7pm'), isNull);
    expect(ask('spent 250 on lunch'), isNull);
    expect(ask('when is the exam?'), isNull);
    expect(ask('good morning team meeting at 9'), isNull);
    expect(ask('next week gym'), isNull);
  });
}
