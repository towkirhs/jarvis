import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/decide.dart';

void main() {
  group('reading answers', () {
    const qs = [
      Question.choice('pick', 'Study or party?', ['Study', 'Party']),
      Question.score('impact', 'How much does it matter?'),
      Question.yesno('wait', 'Can it wait?'),
    ];

    test('typed answers come back sorted, normalised, with confidence', () {
      final a = Decide.parse(
          '```json\n{"answers":[{"id":"pick","probs":{"party":0.2,"study":0.6}},'
          '{"id":"impact","probs":{"4":0.5,"5":0.5}},{"id":"wait","probs":{"yes":0.1,"no":0.9}}]}\n```',
          qs);
      expect(a[0].pick, 'Study');
      expect(a[0].confidence, closeTo(0.75, 1e-9));
      expect(a[1].value, closeTo(4.5, 1e-9));
      expect(a[2].pick, 'no');
      expect(a[2].value, closeTo(0.1, 1e-9));
    });

    test('made-up options are dropped and a missing answer is an even spread', () {
      final a = Decide.parse('{"answers":[{"id":"pick","probs":{"Study":0.5,"Sleep":0.5}}]}', qs);
      expect(a[0].probs, {'Study': 1.0, 'Party': 0.0});
      expect(a[2].confidence, 0.5); // no answer for "wait": nobody should act on it
    });

    test('garbage gives even spreads, never a crash', () {
      final a = Decide.parse('sorry, I cannot help', qs);
      expect(a.map((x) => x.confidence).toList(), [0.5, 0.2, 0.5]);
    });

    test('a choice without options takes the options the AI named', () {
      final a = Decide.parse('{"answers":[{"id":"x","probs":{"Bus":3,"Rickshaw":-1}}]}', const [Question.choice('x', 'How to go?')]);
      expect(a.single.probs, {'Bus': 1.0, 'Rickshaw': 0.0}); // clamped to 0..1
    });
  });

  test('spotting a request to decide', () {
    expect(Decide.isDecisionRequest('Should I go to the wedding on Friday?'), isTrue);
    expect(Decide.isDecisionRequest('rickshaw or bus to campus?'), isTrue);
    expect(Decide.isDecisionRequest('Jarvis decide: pizza tonight'), isTrue);
    expect(Decide.isDecisionRequest('Call Ammu or Abbu tomorrow at 9'), isFalse); // not a question
    expect(Decide.isDecisionRequest('spent 250 on lunch'), isFalse);
  });

  group('what now', () {
    final now = DateTime(2026, 11, 6, 14, 0);
    int at(int h, [int day = 6]) => DateTime(2026, 11, day, h).millisecondsSinceEpoch;
    Map<String, dynamic> task(int id, {int? when, int priority = 0, int est = 30, int postponed = 0}) =>
        {'id': id, 'kind': 'task', 'status': 'open', 'when': when, 'priority': priority, 'est': est, 'postponed': postponed};

    test('overdue and urgent beats someday; tomorrow is left out', () {
      final a = Decide.whatNow([
        task(1),
        task(2, when: at(10), priority: 3), // overdue, high
        task(3, when: at(16)),
        task(4, when: at(9, 7)), // tomorrow
      ], now);
      expect(a.probs.keys.toList(), ['2', '3', '1']);
      expect(a.confidence, greaterThan(0.8));
    });

    test('a long task that does not fit before the next class drops', () {
      final a = Decide.whatNow([
        {'id': 9, 'kind': 'event', 'status': 'open', 'when': at(15)},
        task(1, est: 120),
        task(2, est: 30),
      ], now);
      expect(a.pick, '2');
    });

    test('nothing to do', () {
      expect(Decide.whatNow([], now).pick, 'nothing');
    });
  });
}
