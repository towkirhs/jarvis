import 'habit_core.dart';

/// Lays today's tasks into the free time between fixed events, on the phone, with no AI.
/// Pure Dart so it can be tested on its own.
class PlanBlock {
  PlanBlock(this.title, this.start, this.minutes, {this.itemId, this.fixed = false});
  final String title;
  final DateTime start;
  final int minutes;
  final int? itemId;

  /// An event that was already at this time (not moved by the plan).
  final bool fixed;

  DateTime get end => start.add(Duration(minutes: minutes));
}

/// A change to one proposed task: a time of its own, a length of its own, or left out of today.
class PlanEdit {
  const PlanEdit({this.start, this.minutes, this.skip = false});
  final DateTime? start;
  final int? minutes;
  final bool skip;

  PlanEdit copyWith({DateTime? start, int? minutes, bool? skip, bool clearStart = false}) =>
      PlanEdit(start: clearStart ? null : (start ?? this.start), minutes: minutes ?? this.minutes, skip: skip ?? this.skip);
}

class DayPlan {
  DayPlan(this.blocks, this.overflow, [this.skipped = const [], this.quick = const []]);

  /// Quick tasks (a call, a payment): done any time, so they get no block.
  final List<PlanBlock> quick;

  /// Tasks the person left out of today's plan.
  final List<PlanBlock> skipped;

  /// Events and placed tasks, in time order.
  final List<PlanBlock> blocks;

  /// Tasks that do not fit today, with how long they would take.
  final List<PlanBlock> overflow;
}

class DayPlanner {
  static const _quickVerbs = [
    'call', 'phone', 'text', 'message', 'msg', 'whatsapp', 'reply', 'pay', 'send', 'email', 'mail', 'log',
    'transfer', 'recharge', 'order', 'book', 'ask', 'remind', 'tell', 'save',
  ];

  /// A task that needs no time block: marked so (`quick`), five minutes or less, or starting with a verb
  /// like call, pay or send. `quick: false` keeps a block whatever the title.
  static bool isQuick(Map<String, dynamic> i) {
    final q = i['quick'];
    if (q is bool) return q;
    final est = i['est'] as int?;
    if (est != null && est <= 5) return true;
    final first = '${i['title'] ?? ''}'.trim().toLowerCase().split(RegExp(r'\s+')).first;
    return _quickVerbs.contains(first);
  }

  /// Habits due today that take time, as tasks for the plan. Their id is minus the habit's id.
  /// A habit takes time when it has `planMin` (minutes, 0 = never), or is a duration habit (its target).
  /// Habits already done today, archived, not due today, or already on today's calendar are left out.
  static List<Map<String, dynamic>> habitTasks(List<Map<String, dynamic>> habits, DateTime now, {List<Map<String, dynamic>> items = const []}) {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1)).millisecondsSinceEpoch;
    bool onCalendar(Map<String, dynamic> h) => items.any((i) =>
        i['kind'] == 'event' &&
        (i['planHabit'] == h['id'] || i['habitId'] == h['id']) &&
        i['when'] is int &&
        (i['when'] as int) >= today.millisecondsSinceEpoch &&
        (i['when'] as int) < tomorrow);
    return [
      for (final h in habits)
        if (h['archived'] != true && HabitCore.scheduled(h, today) && !HabitCore.done(h, today) && !onCalendar(h))
          if (((h['planMin'] as num?) ?? (h['type'] == 'duration' ? (h['target'] as num?) : null) ?? 0) > 0)
            {
              'id': -(h['id'] as int),
              'kind': 'task',
              'title': h['name'],
              'est': ((h['planMin'] as num?) ?? (h['target'] as num)).round(),
              'priority': 0,
              'habitId': h['id'],
            },
    ];
  }

  /// [items] are open items. [ratios] maps a category to how much longer the person usually takes
  /// than they estimate (from finished tasks). Tasks are placed most urgent first: overdue, then by
  /// priority, then vital (Pareto) first, then by deadline; tasks dated after today are left alone.
  static DayPlan plan({
    required DateTime now,
    required List<Map<String, dynamic>> items,
    Map<String, double> ratios = const {},
    Map<int, PlanEdit> edits = const {},
    int dayStartHour = 8,
    int dayEndHour = 22,
    int buffer = 10,
    int defaultMinutes = 30,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    DateTime? when(Map<String, dynamic> i) =>
        i['when'] == null ? null : DateTime.fromMillisecondsSinceEpoch(i['when'] as int);

    // Fixed: today's timed events.
    final fixed = <PlanBlock>[
      for (final i in items)
        if (i['kind'] == 'event' && i['allDay'] != true && when(i) != null && !when(i)!.isBefore(today) && when(i)!.isBefore(tomorrow))
          PlanBlock(i['title'] as String, when(i)!, (i['dur'] as int?) ?? 60, itemId: i['id'] as int?, fixed: true),
    ]..sort((a, b) => a.start.compareTo(b.start));

    // To place: tasks without a date, due today, or overdue.
    final quick = <PlanBlock>[
      for (final i in items)
        if (i['kind'] == 'task' && isQuick(i) && (when(i) == null || when(i)!.isBefore(tomorrow)))
          PlanBlock(i['title'] as String, today, 0, itemId: i['id'] as int?),
    ];
    final candidates = items.where((i) {
      if (i['kind'] != 'task' || isQuick(i)) return false;
      final w = when(i);
      return w == null || w.isBefore(tomorrow);
    }).toList();
    final tasks = candidates.where((i) => edits[i['id']]?.skip != true && edits[i['id']]?.start == null).toList()
      ..sort((a, b) {
        int rank(Map<String, dynamic> i) {
          final w = when(i);
          if (w != null && w.isBefore(today)) return 0; // overdue
          if (w != null) return 1; // due today
          return 2; // no date
        }

        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        final p = ((b['priority'] as int?) ?? 0).compareTo((a['priority'] as int?) ?? 0);
        if (p != 0) return p;
        final v = (b['vital'] == true ? 1 : 0).compareTo(a['vital'] == true ? 1 : 0);
        if (v != 0) return v;
        final wa = when(a);
        final wb = when(b);
        if (wa != null && wb != null) return wa.compareTo(wb);
        return 0;
      });

    int length(Map<String, dynamic> i) {
      final own = edits[i['id']]?.minutes;
      if (own != null) return own;
      final est = (i['est'] as int?) ?? defaultMinutes;
      final ratio = ratios[i['cat']] ?? 1.0;
      final m = (est * ratio / 5).round() * 5;
      return m < 10 ? 10 : m;
    }

    // Start at the next 5 minutes from now (or the start of the day), end at the end of the day.
    var cursor = now.isBefore(today.add(Duration(hours: dayStartHour)))
        ? today.add(Duration(hours: dayStartHour))
        : DateTime(now.year, now.month, now.day, now.hour, (now.minute ~/ 5 + 1) * 5);
    final dayEnd = today.add(Duration(hours: dayEndHour));

    // Tasks the person pinned to a time stay there; the rest flow around them like around events.
    final pinned = <PlanBlock>[
      for (final i in candidates)
        if (edits[i['id']]?.skip != true && edits[i['id']]?.start != null)
          PlanBlock(i['title'] as String, edits[i['id']]!.start!, length(i), itemId: i['id'] as int?),
    ];
    final skipped = <PlanBlock>[
      for (final i in candidates)
        if (edits[i['id']]?.skip == true) PlanBlock(i['title'] as String, today, length(i), itemId: i['id'] as int?),
    ];
    final occupied = [...fixed, ...pinned]..sort((a, b) => a.start.compareTo(b.start));

    // Free gaps between the fixed events and pinned tasks.
    final gaps = <(DateTime, DateTime)>[];
    for (final f in occupied) {
      if (f.start.isAfter(cursor)) gaps.add((cursor, f.start.isBefore(dayEnd) ? f.start : dayEnd));
      if (f.end.isAfter(cursor)) cursor = f.end;
    }
    if (dayEnd.isAfter(cursor)) gaps.add((cursor, dayEnd));

    final placed = <PlanBlock>[];
    final overflow = <PlanBlock>[];
    for (final t in tasks) {
      final m = length(t);
      var done = false;
      for (var g = 0; g < gaps.length && !done; g++) {
        final (start, end) = gaps[g];
        if (start.add(Duration(minutes: m)).isAfter(end)) continue;
        placed.add(PlanBlock(t['title'] as String, start, m, itemId: t['id'] as int?));
        gaps[g] = (start.add(Duration(minutes: m + buffer)), end);
        done = true;
      }
      if (!done) overflow.add(PlanBlock(t['title'] as String, today, m, itemId: t['id'] as int?));
    }
    final blocks = [...fixed, ...pinned, ...placed]..sort((a, b) => a.start.compareTo(b.start));
    return DayPlan(blocks, overflow, skipped, quick);
  }
}
