import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/day_planner.dart';
import 'package:jarcis/needs.dart';

class _F implements NeedFacts {
  _F({this.pieces = const {}, this.cash = 0, this.running = true});
  final Map<int, String> pieces;
  final num cash;
  final bool running;
  @override
  String piece(int id) => pieces[id] ?? 'missed';
  @override
  num? balance(String account) => account == 'Cash' ? cash : null;
  @override
  bool? countdownRunning(int id) => id == 1 ? running : null;
}

String _name(String kind, int id) => '$kind$id';
NeedResult _state(Object needs, _F f) => Needs.state(needs, f, name: _name);
Map<String, dynamic> _done(int id, {bool not = false}) => {'check': 'done', 'id': id, 'not': not};

void main() {
  group('where a linked piece stands', () {
    test('B only if A is done: after A while A is open, on once A is done, off if A is missed', () {
      final needs = {'if': [_done(1)]};
      final open = _state(needs, _F(pieces: {1: 'open'}));
      expect(open.state, NeedState.after);
      expect(open.after, [1]);
      expect(open.why, 'Once task1 is done');
      expect(_state(needs, _F(pieces: {1: 'done'})).state, NeedState.met);
      expect(_state(needs, _F(pieces: {1: 'missed'})).state, NeedState.off);
    });

    test('D only if A is not done: on standby while A is open, on when A is missed, off when A is done', () {
      final needs = {'if': [_done(1, not: true)]};
      expect(_state(needs, _F(pieces: {1: 'open'})).state, NeedState.standby);
      expect(_state(needs, _F(pieces: {1: 'missed'})).state, NeedState.met);
      expect(_state(needs, _F(pieces: {1: 'done'})).state, NeedState.off);
    });

    test('a habit is a piece too (minus its id), and money can be a condition', () {
      final needs = {'if': [_done(-7, not: true), {'check': 'balance', 'account': 'Cash', 'atLeast': 500}]};
      expect(_state(needs, _F(pieces: {-7: 'missed'}, cash: 600)).state, NeedState.met);
      final poor = _state(needs, _F(pieces: {-7: 'missed'}, cash: 100));
      expect(poor.state, NeedState.off);
      expect(poor.why, 'Needs: Cash has at least 500');
    });

    test('"or": one is enough', () {
      final needs = {'any': true, 'if': [_done(1), _done(2)]};
      expect(_state(needs, _F(pieces: {1: 'missed', 2: 'done'})).state, NeedState.met);
      expect(_state(needs, _F(pieces: {1: 'missed', 2: 'open'})).state, NeedState.after);
      expect(_state(needs, _F(pieces: {1: 'missed', 2: 'missed'})).state, NeedState.off);
    });

    test('until a countdown ends, and then something else instead', () {
      final a = {'if': [{'check': 'countdown', 'id': 1}]};
      final c = Needs.opposite(a);
      expect(_state(a, _F()).state, NeedState.met);
      expect(_state(c, _F()).state, NeedState.off);
      expect(_state(a, _F(running: false)).state, NeedState.off);
      expect(_state(c, _F(running: false)).state, NeedState.met);
    });

    test('"counts as done when" holds only when everything is true now', () {
      final both = {'if': [_done(-1), _done(-2)]};
      expect(Needs.holdsNow(both, _F(pieces: {-1: 'done', -2: 'open'})), false);
      expect(Needs.holdsNow(both, _F(pieces: {-1: 'done', -2: 'done'})), true);
      expect(Needs.holdsNow(null, _F()), false);
    });
  });

  group('the planner with links', () {
    final now = DateTime(2026, 11, 5, 9, 2);
    final sat = DateTime(2026, 11, 7);
    int at(int h) => DateTime(2026, 11, 7, h).millisecondsSinceEpoch;
    Map<String, dynamic> task(int id, String title, int est, {int priority = 0, int? chunk}) =>
        {'id': id, 'kind': 'task', 'title': title, 'est': est, 'priority': priority, 'when': at(9), if (chunk != null) 'chunk': chunk};
    String hm(DateTime d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    List<String> view(DayPlan p) => p.blocks.map((b) => '${hm(b.start)}-${hm(b.end)} ${b.title}').toList();

    test('a piece that follows another is placed after it, whatever its priority', () {
      final p = DayPlanner.plan(now: now, day: sat, items: [
        task(1, 'Revise', 60, priority: 3),
        task(2, 'Class notes', 60),
      ], needs: const {1: NeedResult(NeedState.after, after: [2], why: 'Once Class notes is done')});
      expect(view(p), ['8:00-9:00 Class notes', '9:10-10:10 Revise']);
    });

    test('a fallback and a piece whose condition fails get no time', () {
      final p = DayPlanner.plan(now: now, day: sat, items: [
        task(1, 'Gym', 60),
        task(2, 'Walk', 30),
        task(3, 'Buy shoes', 30),
      ], needs: const {
        2: NeedResult(NeedState.standby, why: 'Only if Gym is not done'),
        3: NeedResult(NeedState.off, why: 'Needs: Cash has at least 500'),
      });
      expect(view(p), ['8:00-9:00 Gym']);
      expect(p.standby.single.title, 'Walk');
      expect(p.off.single.reason, 'Needs: Cash has at least 500');
    });

    test('an 8 hour task in 2 hour blocks: four blocks, less what its parts already cover', () {
      final study = task(1, 'Thesis', 480, chunk: 120);
      final p = DayPlanner.plan(now: now, day: sat, items: [study]);
      expect(view(p), ['8:00-10:00 Thesis', '10:10-12:10 Thesis', '12:20-14:20 Thesis', '14:30-16:30 Thesis']);
      expect(p.blocks.map((b) => b.part), [1, 2, 3, 4]);

      final withPart = DayPlanner.plan(now: now, day: sat, items: [
        study,
        {'id': 9, 'kind': 'task', 'title': 'Thesis', 'est': 240, 'partOf': 1, 'when': DateTime(2026, 11, 6, 9).millisecondsSinceEpoch, 'status': 'done'},
      ]);
      expect(withPart.blocks.length, 2);
    });

    test('you can do only some blocks on a day; the rest is noted for other days', () {
      final p = DayPlanner.plan(now: now, day: sat, items: [task(1, 'Thesis', 480, chunk: 120)], edits: const {1: PlanEdit(blocks: 2)});
      expect(p.blocks.length, 2);
      expect(p.overflow, isEmpty);
      expect(p.notes.join(' '), contains('Thesis: 4h is left for other days'));
    });

    test("the day's own priority beats the usual one", () {
      final p = DayPlanner.plan(now: now, day: sat, items: [
        task(1, 'Important overall', 60, priority: 3),
        {...task(2, 'Important today', 60), 'dayPri': {'day': '2026-11-07', 'p': 3}},
        {...task(3, 'Was important another day', 60), 'dayPri': {'day': '2026-11-01', 'p': 3}},
      ]);
      expect(p.blocks.map((b) => b.title).toList(), ['Important overall', 'Important today', 'Was important another day']);
      final q = DayPlanner.plan(now: now, day: sat, items: [
        {...task(1, 'Important overall', 60, priority: 3), 'dayPri': {'day': '2026-11-07', 'p': 0}},
        {...task(2, 'Important today', 60), 'dayPri': {'day': '2026-11-07', 'p': 3}},
      ]);
      expect(q.blocks.first.title, 'Important today');
    });

    test('habits are pieces: timed ones get a block on any day, the rest are quick, one added by hand gets 30 minutes', () {
      final habits = <Map<String, dynamic>>[
        {'id': 1, 'name': 'Gym', 'type': 'yesno', 'planMin': 60, 'start': '2026-01-01', 'sched': {'kind': 'daily'}, 'logs': <String, dynamic>{}},
        {'id': 2, 'name': 'Vitamins', 'type': 'yesno', 'start': '2026-01-01', 'sched': {'kind': 'daily'}, 'logs': <String, dynamic>{}},
        {'id': 3, 'name': 'Read', 'type': 'yesno', 'start': '2026-01-01', 'sched': {'kind': 'once'}, 'logs': <String, dynamic>{}},
      ];
      final pieces = DayPlanner.habitTasks(habits, sat, extra: {-3});
      final p = DayPlanner.plan(now: now, day: sat, items: pieces);
      expect(view(p), ['8:00-9:00 Gym', '9:10-9:40 Read']);
      expect(p.quick.single.title, 'Vitamins');
    });
  });
}
