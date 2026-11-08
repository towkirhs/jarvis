import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/destination.dart';

void main() {
  (String, String)? d(String t) {
    final x = Destination.of(t);
    return x == null ? null : (x.type, x.rest);
  }

  test('a word at the start says where it goes', () {
    expect(d('calendar: dinner with Oishi Friday 8pm'), ('event', 'dinner with Oishi Friday 8pm'));
    expect(d('Calendar dinner Friday 8pm'), ('event', 'dinner Friday 8pm'));
    expect(d('task: buy milk'), ('task', 'buy milk'));
    expect(d('todo call the plumber'), ('task', 'call the plumber'));
    expect(d('To-do - submit the form'), ('task', 'submit the form'));
    expect(d('alarm: gym 6am'), ('alarm', 'gym 6am'));
    expect(d('journal: today was a good day, I meditated'), ('note', 'today was a good day, I meditated'));
    expect(d('diary, felt tired after class'), ('note', 'felt tired after class'));
    expect(d('note: I want to learn guitar someday'), ('note', 'I want to learn guitar someday'));
  });

  test('"add to my calendar" at the start or the end', () {
    expect(d('add to my calendar: exam on 12 Dec'), ('event', 'exam on 12 Dec'));
    expect(d('put in my tasks renew passport'), ('task', 'renew passport'));
    expect(d('Dinner with Oishi Friday 8pm, add it to my calendar'), ('event', 'Dinner with Oishi Friday 8pm'));
    expect(d('meeting with Rafi tomorrow 3pm to my calendar.'), ('event', 'meeting with Rafi tomorrow 3pm'));
    expect(d('felt calm today in my journal'), ('note', 'felt calm today'));
    expect(d('buy eggs to my to-do list'), ('task', 'buy eggs'));
  });

  test('ordinary sentences are left alone', () {
    expect(d('note that I need to call Ammu'), isNull);
    expect(d('tasks for today?'), isNull);
    expect(d('I went to the event yesterday'), isNull);
    expect(d('buy milk tomorrow'), isNull);
    expect(d('calendar:'), isNull);
    expect(d('eventually I will go'), isNull);
  });

  test('forcing turns tasks, events and alarms into the kind you said', () {
    const cal = Destination('event', 'dinner Friday 8pm');
    final ai = {
      'items': [
        {'type': 'task', 'title': 'Dinner', 'date': '2026-11-13', 'time': '20:00'},
        {'type': 'money', 'amount': 500},
      ]
    };
    final f = Destination.force(ai, cal);
    expect([for (final i in f['items'] as List) i['type']], ['event', 'money']);
    expect(((f['items'] as List).first as Map)['time'], '20:00');

    // Nothing of that kind came back (no AI, or it said "note"): one is made from the note.
    final g = Destination.force({'items': [{'type': 'note'}]}, const Destination('task', 'buy milk'));
    expect(g['items'], [
      {'type': 'task', 'title': 'buy milk', 'confidence': 1}
    ]);
  });
}
