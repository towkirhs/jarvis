import 'habit_core.dart';
import 'needs.dart';
import 'store.dart';

/// Answers a piece's links and conditions from the Store, for [day] (today when null).
/// [skipped] are pieces left out of that day's plan; [present], when given, are the pieces on that day's plan.
class PieceFacts implements NeedFacts {
  PieceFacts(this.s, {DateTime? day, this.skipped = const {}, this.present}) : day = day ?? DateTime.now();
  final Store s;
  final DateTime day;
  final Set<int> skipped;
  final Set<int>? present;

  @override
  String piece(int id) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(day.year, day.month, day.day);
    if (id < 0) {
      final h = s.byId('habits', -id);
      if (h == null) return 'missed';
      if (HabitCore.done(h, d)) return 'done';
      return skipped.contains(id) || d.isBefore(today) ? 'missed' : 'open';
    }
    final it = s.byId('items', id);
    if (it == null) return 'missed';
    if (it['status'] == 'done') return 'done';
    if (it['status'] != 'open' || skipped.contains(id)) return 'missed';
    if (present != null && !present!.contains(id)) return 'missed';
    final when = it['when'] as int?;
    if (when == null) return 'open';
    final w = fromMs(when);
    // On a later day: not part of this one.
    if (present == null && DateTime(w.year, w.month, w.day).isAfter(d)) return 'missed';
    // Its planned time today has gone by.
    if (it['allDay'] != true && dayKey(w) == dayKey(d) && d == today) {
      final end = w.add(Duration(minutes: (it['est'] as int?) ?? 30));
      if (end.isBefore(now)) return 'missed';
    }
    return 'open';
  }

  @override
  num? balance(String account) {
    for (final a in s.list('accounts')) {
      if ('${a['name']}'.toLowerCase() == account.trim().toLowerCase()) return s.balance(a);
    }
    return null;
  }

  @override
  bool? countdownRunning(int id) {
    final c = s.byId('countdowns', id);
    if (c == null) return null;
    return !s.countdownNext(c).isBefore(DateTime(day.year, day.month, day.day));
  }

  /// A piece's or countdown's title, for sentences.
  String name(String kind, int id) => switch (kind) {
        'habit' => '${s.byId('habits', id)?['name'] ?? 'a habit'}',
        'countdown' => '${s.byId('countdowns', id)?['title'] ?? 'a countdown'}',
        _ => '${s.byId('items', id)?['title'] ?? 'a task'}',
      };

  /// The needs of an item: a habit's planned task carries its habit's.
  Object? needsOf(Rec it) {
    if (it['planHabit'] is! int) return it['needs'];
    return (s.byId('habits', it['planHabit'] as int) ?? const {})['needs'];
  }

  NeedResult stateOf(Object? needs) => Needs.state(needs, this, name: name, money: s.money);
}
