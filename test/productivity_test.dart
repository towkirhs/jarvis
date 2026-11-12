import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/day_planner.dart';
import 'package:jarcis/productivity.dart';

void main() {
  final now = DateTime(2026, 11, 12, 10); // a Thursday
  int ms(DateTime d) => d.millisecondsSinceEpoch;

  group('Active recall (Leitner boxes)', () {
    test('a right answer moves the card up a box and further away; a miss sends it back to box 0', () {
      expect(Recall.review(0, true, now), (box: 1, due: ms(DateTime(2026, 11, 14))));
      expect(Recall.review(3, true, now), (box: 4, due: ms(DateTime(2026, 11, 28))));
      expect(Recall.review(4, false, now), (box: 0, due: ms(DateTime(2026, 11, 13))));
      expect(Recall.review(Recall.gaps.length - 1, true, now).box, Recall.gaps.length - 1);
    });

    test('a card is due on or before today', () {
      expect(Recall.isDue({'due': ms(DateTime(2026, 11, 12, 23))}, now), true);
      expect(Recall.isDue({'due': ms(DateTime(2026, 11, 13))}, now), false);
      expect(Recall.isDue({}, now), true);
    });
  });

  test('Pareto: about one task in five is vital', () {
    expect([Pareto.target(0), Pareto.target(1), Pareto.target(5), Pareto.target(12)], [0, 1, 1, 3]);
  });

  group('the one thing to do now', () {
    Map<String, dynamic> task(int id, {int p = 0, bool vital = false, DateTime? when, String kind = 'task'}) =>
        {'id': id, 'kind': kind, 'status': 'open', 'title': 't$id', 'priority': p, if (vital) 'vital': true, if (when != null) 'when': ms(when)};

    test('urgent and important wins, then vital, then the sooner deadline', () {
      final items = [
        task(1, p: 2, vital: true),
        task(2, p: 3, when: DateTime(2026, 11, 20)),
        task(3, p: 3, vital: true, when: DateTime(2026, 11, 25)),
        task(4, p: 3, vital: true, when: DateTime(2026, 11, 22)),
      ];
      expect(Engine.topTask(items)?['id'], 4);
      expect(Engine.topTask(items.where((i) => i['priority'] != 3))?['id'], 1);
    });

    test('events, done tasks and Someday or Waiting tasks are not picked', () {
      expect(Engine.topTask([task(1, kind: 'event', p: 3), {...task(2, p: 3), 'status': 'done'}]), isNull);
      expect(Engine.topTask([{...task(1, p: 3), 'list': 'Someday'}, {...task(2), 'list': 'Waiting'}]), isNull);
    });
  });

  test('deep work minutes count only deep sessions since Monday', () {
    final f = [
      {'start': ms(DateTime(2026, 11, 9, 8)), 'minutes': 90, 'deep': true},
      {'start': ms(DateTime(2026, 11, 12, 8)), 'minutes': 25},
      {'start': ms(DateTime(2026, 11, 8, 8)), 'minutes': 90, 'deep': true},
    ];
    expect(Engine.deepMinutesThisWeek(f, now), 90);
  });

  test('the weekly review is due after seven days, or if never done', () {
    expect(Gtd.reviewDue(null, now), true);
    expect(Gtd.reviewDue(ms(DateTime(2026, 11, 6)), now), false);
    expect(Gtd.reviewDue(ms(DateTime(2026, 11, 4)), now), true);
  });

  test('the day plan places vital tasks before others of the same priority', () {
    final plan = DayPlanner.plan(now: now, items: [
      {'id': 1, 'kind': 'task', 'status': 'open', 'title': 'a', 'priority': 2, 'est': 600},
      {'id': 2, 'kind': 'task', 'status': 'open', 'title': 'b', 'priority': 2, 'est': 60, 'vital': true},
    ]);
    expect(plan.blocks.first.itemId, 2);
  });
}
