import 'cal_index.dart';
import 'habit_core.dart';
import 'store.dart' show dayKey, fmtMinutes;

/// Lays today's tasks into the free time between fixed events, on the phone, with no AI.
/// Pure Dart so it can be tested on its own.
class PlanBlock {
  PlanBlock(this.title, this.start, this.minutes, {this.itemId, this.fixed = false, this.reason});
  final String title;
  final DateTime start;
  final int minutes;
  final int? itemId;

  /// An event that was already at this time (not moved by the plan).
  final bool fixed;

  /// For a task that did not fit: why.
  final String? reason;

  DateTime get end => start.add(Duration(minutes: minutes));
}

/// A change to one proposed task: a time of its own, a length of its own (and a longest length),
/// a time window it must stay inside, or left out of the day. The window and the longest length
/// are the task's own (`winFrom`, `winTo`, `estMax` on the item); here they override it.
class PlanEdit {
  const PlanEdit({this.start, this.minutes, this.skip = false, this.from, this.to, this.max, this.noWindow = false});
  final DateTime? start;
  final int? minutes;
  final bool skip;

  /// Window, in minutes after midnight.
  final int? from;
  final int? to;

  /// The longest the task may take.
  final int? max;

  /// Ignore the window the task has.
  final bool noWindow;

  PlanEdit copyWith({DateTime? start, int? minutes, bool? skip, bool clearStart = false, int? from, int? to, int? max, bool? noWindow}) => PlanEdit(
        start: clearStart ? null : (start ?? this.start),
        minutes: minutes ?? this.minutes,
        skip: skip ?? this.skip,
        from: (noWindow ?? this.noWindow) ? null : (from ?? this.from),
        to: (noWindow ?? this.noWindow) ? null : (to ?? this.to),
        max: max ?? this.max,
        noWindow: noWindow ?? this.noWindow,
      );
}

class DayPlan {
  DayPlan(this.blocks, this.overflow, [this.skipped = const [], this.quick = const [], this.notes = const []]);

  /// What Jarvis worked out: how much time is spare, what was stretched, what is outside its window.
  final List<String> notes;

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

  static String _hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  /// [items] are open items. [day] is the day to plan (today when null); [extra] are task ids added to
  /// that day by hand. [ratios] maps a category to how much longer the person usually takes than they
  /// estimate (from finished tasks).
  ///
  /// A task is for the day when it is dated that day or added by hand; today also takes tasks with no date
  /// and overdue ones. A task has `est` minutes, may have a longest length `estMax`, and may have a time
  /// window `winFrom`/`winTo` (minutes after midnight) it must stay inside. Tasks with a window are placed
  /// first, the ones with the earliest end first, because they have the fewest choices; the rest follow
  /// most urgent first: overdue, priority, vital (Pareto), deadline. Every task gets its shortest length;
  /// the time left over is then given to tasks with a longest length.
  static DayPlan plan({
    required DateTime now,
    DateTime? day,
    Set<int> extra = const {},
    required List<Map<String, dynamic>> items,
    Map<String, double> ratios = const {},
    Map<int, PlanEdit> edits = const {},
    int dayStartHour = 8,
    int dayEndHour = 22,
    int buffer = 10,
    int defaultMinutes = 30,
  }) {
    final d = day ?? now;
    final today = DateTime(d.year, d.month, d.day);
    final tomorrow = DateTime(d.year, d.month, d.day + 1);
    final isToday = dayKey(today) == dayKey(now);
    DateTime? when(Map<String, dynamic> i) =>
        i['when'] == null ? null : DateTime.fromMillisecondsSinceEpoch(i['when'] as int);

    // Fixed: the day's timed events, repeats included.
    final fixed = <PlanBlock>[
      for (final e in CalIndex.build([for (final i in items) if (i['kind'] == 'event') i], today, today)[dayKey(today)] ?? const <CalEntry>[])
        if (e.item['allDay'] != true)
          PlanBlock('${e.item['title']}', e.start, (e.item['dur'] as int?) ?? 60, itemId: e.item['ext'] == null ? e.item['id'] as int? : null, fixed: true),
    ]..sort((a, b) => a.start.compareTo(b.start));

    bool wanted(Map<String, dynamic> i) {
      final w = when(i);
      if (extra.contains(i['id'])) return true;
      if (w != null && !w.isBefore(today) && w.isBefore(tomorrow)) return true;
      return isToday && (w == null || w.isBefore(tomorrow));
    }

    // To place: tasks for the day.
    final quick = <PlanBlock>[
      for (final i in items)
        if (i['kind'] == 'task' && isQuick(i) && wanted(i)) PlanBlock(i['title'] as String, today, 0, itemId: i['id'] as int?),
    ];
    final candidates = items.where((i) => i['kind'] == 'task' && !isQuick(i) && wanted(i)).toList();

    (int, int)? window(Map<String, dynamic> i) {
      final e = edits[i['id']];
      if (e?.noWindow == true) return null;
      final f = e?.from ?? (i['winFrom'] as num?)?.toInt();
      final t = e?.to ?? (i['winTo'] as num?)?.toInt();
      if (f == null && t == null) return null;
      return (f ?? 0, t ?? 1440);
    }

    final tasks = candidates.where((i) => edits[i['id']]?.skip != true && edits[i['id']]?.start == null).toList()
      ..sort((a, b) {
        int rank(Map<String, dynamic> i) {
          final w = when(i);
          if (w != null && w.isBefore(today)) return 0; // overdue
          if (w != null) return 1; // due that day
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
    final ordered = [
      ...(tasks.where((i) => window(i) != null).toList()
        ..sort((a, b) {
          final wa = window(a)!;
          final wb = window(b)!;
          final c = wa.$2.compareTo(wb.$2);
          if (c != 0) return c;
          final f = wa.$1.compareTo(wb.$1);
          if (f != 0) return f;
          return ((b['priority'] as int?) ?? 0).compareTo((a['priority'] as int?) ?? 0);
        })),
      ...tasks.where((i) => window(i) == null),
    ];

    int length(Map<String, dynamic> i) {
      final own = edits[i['id']]?.minutes;
      if (own != null) return own;
      final est = (i['est'] as int?) ?? defaultMinutes;
      final ratio = ratios[i['cat']] ?? 1.0;
      final m = (est * ratio / 5).round() * 5;
      return m < 10 ? 10 : m;
    }

    int longest(Map<String, dynamic> i) {
      final m = edits[i['id']]?.max ?? (i['estMax'] as num?)?.toInt() ?? 0;
      final l = length(i);
      return m > l ? m : l;
    }

    // Start at the next 5 minutes from now (today) or at the start of the day, end at the end of the day.
    final startOfDay = today.add(Duration(hours: dayStartHour));
    var cursor = isToday && !now.isBefore(startOfDay)
        ? DateTime(now.year, now.month, now.day, now.hour, (now.minute ~/ 5 + 1) * 5)
        : startOfDay;
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
    final freeMin = gaps.fold<int>(0, (a, g) => a + g.$2.difference(g.$1).inMinutes);

    final placed = <PlanBlock>[];
    final placedTasks = <Map<String, dynamic>>[];
    final overflow = <PlanBlock>[];
    for (final t in ordered) {
      final m = length(t);
      final win = window(t);
      final from = win == null ? null : today.add(Duration(minutes: win.$1));
      final to = win == null ? null : today.add(Duration(minutes: win.$2));
      var done = false;
      for (var g = 0; g < gaps.length && !done; g++) {
        final (gs, ge) = gaps[g];
        final start = from != null && from.isAfter(gs) ? from : gs;
        final end = to != null && to.isBefore(ge) ? to : ge;
        if (start.add(Duration(minutes: m)).isAfter(end)) continue;
        placed.add(PlanBlock(t['title'] as String, start, m, itemId: t['id'] as int?));
        placedTasks.add(t);
        final keep = <(DateTime, DateTime)>[
          if (start.difference(gs).inMinutes > buffer) (gs, start.subtract(Duration(minutes: buffer))),
          if (ge.isAfter(start.add(Duration(minutes: m + buffer)))) (start.add(Duration(minutes: m + buffer)), ge),
        ];
        gaps.replaceRange(g, g + 1, keep);
        done = true;
      }
      if (!done) {
        String reason;
        if (win != null && win.$2 - win.$1 < m) {
          reason = 'Its window, ${_hm(win.$1)} to ${_hm(win.$2)}, is shorter than ${fmtMinutes(m)}.';
        } else if (win != null) {
          reason = 'No free ${fmtMinutes(m)} inside its window, ${_hm(win.$1)} to ${_hm(win.$2)}.';
        } else {
          reason = 'No free ${fmtMinutes(m)} left in the day.';
        }
        overflow.add(PlanBlock(t['title'] as String, today, m, itemId: t['id'] as int?, reason: reason));
      }
    }

    // Spare time goes to tasks with a longest length, most urgent first, never into the next block's break.
    final notes = <String>[];
    var stretched = 0;
    for (var k = 0; k < placed.length; k++) {
      final t = placedTasks[k];
      final b = placed[k];
      final most = longest(t);
      if (most <= b.minutes) continue;
      final win = window(t);
      var limit = b.start.add(Duration(minutes: most));
      if (win != null) {
        final to = today.add(Duration(minutes: win.$2));
        if (to.isBefore(limit)) limit = to;
      }
      if (dayEnd.isBefore(limit)) limit = dayEnd;
      for (final o in [...occupied, ...placed]) {
        if (identical(o, b) || o.start.isBefore(b.end)) continue;
        final cap = o.start.subtract(Duration(minutes: buffer));
        if (cap.isBefore(limit)) limit = cap;
      }
      final m = limit.difference(b.start).inMinutes;
      if (m > b.minutes) {
        placed[k] = PlanBlock(b.title, b.start, m, itemId: b.itemId);
        stretched += m - b.minutes;
      }
    }

    // The analysis.
    final need = [for (final t in ordered) length(t)].fold<int>(0, (a, m) => a + m) + buffer * ordered.length;
    if (overflow.isEmpty) {
      if (ordered.isNotEmpty) {
        final spare = freeMin - need;
        notes.add('${fmtMinutes(need - buffer * ordered.length)} of tasks in ${fmtMinutes(freeMin)} free: about ${fmtMinutes(spare < 0 ? 0 : spare)} spare.');
      }
    } else {
      final lack = need - freeMin;
      notes.add(lack > 0
          ? 'The day is short by about ${fmtMinutes(lack)}: ${overflow.length} task${overflow.length == 1 ? '' : 's'} left over.'
          : '${overflow.length} task${overflow.length == 1 ? '' : 's'} left over: they do not fit where their windows are.');
    }
    if (stretched > 0) notes.add('Gave ${fmtMinutes(stretched)} of spare time to tasks that can take longer.');
    for (final b in pinned) {
      final i = candidates.firstWhere((c) => c['id'] == b.itemId);
      final win = window(i);
      if (win == null) continue;
      final from = today.add(Duration(minutes: win.$1));
      final to = today.add(Duration(minutes: win.$2));
      if (b.start.isBefore(from) || b.end.isAfter(to)) notes.add('${b.title} is set outside its window, ${_hm(win.$1)} to ${_hm(win.$2)}.');
    }

    final blocks = [...fixed, ...pinned, ...placed]..sort((a, b) => a.start.compareTo(b.start));
    return DayPlan(blocks, overflow, skipped, quick, notes);
  }
}
