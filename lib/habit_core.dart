/// How habits are measured, scheduled and scored. Pure Dart, tested on its own.
///
/// A habit (all fields optional except id, name, logs; old habits only have times/per and still work):
///  type      one of [HabitType.all] keys; default 'yesno'
///  target    the daily goal: reps, minutes, litres, %, km, completions, the lowest good rating, or the
///            highest allowed amount for a limit. Changes are kept in 'targets' so old days keep their goal.
///  targets   [{from: 'YYYY-MM-DD', v: num}]
///  unit      'L', 'km', 'pages'…   scale  rating scale top (10)   by  'HH:MM' for time habits
///  items     checklist step names
///  goal      build, break, maintain, reduce, increase, target, avoid (what you are aiming for)
///  sched     {kind: daily | days | week | month | every | once, days: [1..7], n: int, date: 'YYYY-MM-DD'}
///            (no sched: n times per 'per', the old weekly or monthly target)
///  start     'YYYY-MM-DD' the first day that counts
///  prog      {by: num, every: days, max: num?} a target that grows over time
///  grace     missed days in a row that do not break a streak
///  off       [[from, to or null]] paused ranges   archived  bool
///  routine   'morning', 'evening' or a name   order  int   after  id of the habit this one follows
///
/// A day's log is 'yes', 'no' (missed), 'skip' (rest day), or a map
/// {v: num, items: [bool], at: 'HH:MM', note, photo, skip: bool, miss: bool, done: bool}.
library;

class HabitType {
  const HabitType(this.key, this.label, this.hint, {this.unit, this.target, this.ready = true});
  final String key;
  final String label;
  final String hint;
  final String? unit;
  final num? target;

  /// False for types that need something this app cannot do yet; shown, but not selectable.
  final bool ready;

  static const all = [
    HabitType('yesno', 'Yes or no', 'Did it or not'),
    HabitType('count', 'Count', 'Reps, like 20 push-ups', unit: 'times', target: 20),
    HabitType('duration', 'Duration', 'Time spent, with a timer', unit: 'min', target: 30),
    HabitType('quantity', 'Quantity', 'An amount, like 3 litres of water', unit: 'L', target: 3),
    HabitType('frequency', 'Times a day', 'Several completions a day', unit: 'times', target: 3),
    HabitType('percent', 'Percentage', 'Progress towards 100%', unit: '%', target: 100),
    HabitType('distance', 'Distance', 'Kilometres or metres', unit: 'km', target: 5),
    HabitType('time', 'By a time', 'Done before a set time, like up by 6:00'),
    HabitType('rating', 'Rating', 'Rate the day, like 1 to 10', target: 7),
    HabitType('checklist', 'Checklist', 'Several steps to tick off'),
    HabitType('limit', 'Limit', 'Stay under a maximum, like 2 h screen time', unit: 'min', target: 120),
    HabitType('auto', 'Automatic', 'Steps from your phone (needs Health Connect, coming)', ready: false),
  ];

  static HabitType of(Map<String, dynamic> h) =>
      all.firstWhere((t) => t.key == (h['type'] ?? 'yesno'), orElse: () => all.first);
}

const goals = {
  'build': 'Build a new habit',
  'break': 'Break a bad habit',
  'maintain': 'Maintain a habit',
  'reduce': 'Reduce something',
  'increase': 'Increase something',
  'target': 'Reach a target',
  'avoid': 'Avoid something',
};

/// A day as 'YYYY-MM-DD'.
String dk(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime pd(String key) => DateTime.parse(key);
DateTime _d(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _plus(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);
int _daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// One scheduled slot: a day (for daily-type schedules) or a week/month (for "n times per week/month").
enum Slot { done, missed, skipped, pending }

class HabitCore {
  // ---------- schedule ----------

  static Map<String, dynamic> sched(Map<String, dynamic> h) {
    final s = h['sched'];
    if (s is Map) return s.cast<String, dynamic>();
    final times = (h['times'] as int?) ?? 3;
    final per = (h['per'] as String?) ?? 'week';
    if (per == 'week' && times >= 7) return {'kind': 'daily'};
    return {'kind': per, 'n': times};
  }

  static String kind(Map<String, dynamic> h) => sched(h)['kind'] as String;

  /// Weekly or monthly targets count completions in a period; the rest are day by day.
  static bool byPeriod(Map<String, dynamic> h) => kind(h) == 'week' || kind(h) == 'month';

  static DateTime start(Map<String, dynamic> h) {
    final s = h['start'] as String?;
    if (s != null) return pd(s);
    final keys = (h['logs'] as Map).keys.cast<String>().toList()..sort();
    return keys.isEmpty ? _d(DateTime.now()) : pd(keys.first);
  }

  static bool paused(Map<String, dynamic> h, DateTime day) {
    final k = dk(day);
    for (final r in (h['off'] as List?) ?? const []) {
      final from = r[0] as String;
      final to = r[1] as String?;
      if (k.compareTo(from) >= 0 && (to == null || k.compareTo(to) <= 0)) return true;
    }
    return false;
  }

  static bool isPaused(Map<String, dynamic> h, DateTime now) => paused(h, now);

  /// Is the habit meant to be done on [day]? (For weekly/monthly targets every day is open.)
  static bool scheduled(Map<String, dynamic> h, DateTime day) {
    final d = _d(day);
    if (d.isBefore(_d(start(h))) || paused(h, d)) return false;
    final s = sched(h);
    switch (s['kind']) {
      case 'days':
        return ((s['days'] as List?) ?? const []).contains(d.weekday);
      case 'every':
        final n = ((s['n'] as int?) ?? 1).clamp(1, 365);
        return _daysBetween(start(h), d) % n == 0;
      case 'once':
        return s['date'] == dk(d);
      default:
        return true; // daily, week, month
    }
  }

  static String describe(Map<String, dynamic> h) {
    final s = sched(h);
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    switch (s['kind']) {
      case 'daily':
        return 'Every day';
      case 'days':
        final days = ((s['days'] as List?) ?? const []).cast<int>()..sort();
        return days.map((d) => names[d - 1]).join(', ');
      case 'every':
        return 'Every ${s['n']} days';
      case 'once':
        return 'Once, on ${s['date']}';
      case 'month':
        return '${s['n']} times a month';
      default:
        return '${s['n']} times a week';
    }
  }

  // ---------- targets ----------

  /// The goal that applied on [day]: the target history, then any progressive increase.
  static num? target(Map<String, dynamic> h, DateTime day) {
    num? t = h['target'] as num?;
    final k = dk(day);
    final history = ((h['targets'] as List?) ?? const []).cast<Map>().toList()
      ..sort((a, b) => (a['from'] as String).compareTo(b['from'] as String));
    for (final e in history) {
      if ((e['from'] as String).compareTo(k) <= 0) t = e['v'] as num;
    }
    final prog = h['prog'] as Map?;
    if (t != null && prog != null) {
      final every = ((prog['every'] as int?) ?? 7).clamp(1, 365);
      final steps = _daysBetween(start(h), day) ~/ every;
      if (steps > 0) {
        t = t + (prog['by'] as num) * steps;
        final max = prog['max'] as num?;
        if (max != null && t > max) t = max;
      }
    }
    return t;
  }

  // ---------- one day ----------

  /// The day's log as a map (old 'yes'/'no' strings included), or null if nothing was logged.
  static Map<String, dynamic>? entry(Map<String, dynamic> h, String day) {
    final v = (h['logs'] as Map)[day];
    if (v == null) return null;
    if (v == 'yes') return {'done': true};
    if (v == 'no') return {'miss': true};
    if (v == 'skip') return {'skip': true};
    return (v as Map).cast<String, dynamic>();
  }

  /// How far the day got, 0 to 1. Null when nothing was logged or it was a rest day.
  static double? progress(Map<String, dynamic> h, DateTime day) {
    final e = entry(h, dk(day));
    if (e == null || e['skip'] == true) return null;
    if (e['miss'] == true) return 0;
    if (e['done'] == true) return 1;
    final type = (h['type'] as String?) ?? 'yesno';
    final v = e['v'] as num?;
    final t = target(h, day);
    switch (type) {
      case 'yesno':
      case 'auto':
        return v != null && v > 0 ? 1 : 0;
      case 'time':
        final at = e['at'] as String?;
        final by = h['by'] as String?;
        if (at == null) return 0;
        return by == null || at.compareTo(by) <= 0 ? 1 : 0;
      case 'checklist':
        final items = ((e['items'] as List?) ?? const []).cast<bool>();
        final total = ((h['items'] as List?) ?? const []).length;
        if (total == 0) return 0;
        return (items.where((x) => x).length / total).clamp(0.0, 1.0);
      case 'limit':
        if (v == null || t == null) return null;
        return v <= t ? 1 : 0;
      case 'rating':
        if (v == null) return null;
        final good = t ?? ((h['scale'] as num?) ?? 10) * 0.7;
        return (v / good).clamp(0.0, 1.0).toDouble();
      default:
        if (v == null) return null;
        if (t == null || t <= 0) return v > 0 ? 1 : 0;
        return (v / t).clamp(0.0, 1.0).toDouble();
    }
  }

  static bool done(Map<String, dynamic> h, DateTime day) => (progress(h, day) ?? 0) >= 1;

  static bool skipped(Map<String, dynamic> h, DateTime day) => entry(h, dk(day))?['skip'] == true;

  /// The logged amount, for numeric habits.
  static num? value(Map<String, dynamic> h, DateTime day) => entry(h, dk(day))?['v'] as num?;

  // ---------- periods ----------

  static DateTime periodStart(Map<String, dynamic> h, DateTime d) =>
      kind(h) == 'month' ? DateTime(d.year, d.month) : _plus(_d(d), -(d.weekday - 1));

  static DateTime nextPeriod(Map<String, dynamic> h, DateTime p) =>
      kind(h) == 'month' ? DateTime(p.year, p.month + 1) : _plus(p, 7);

  static int periodTarget(Map<String, dynamic> h) => ((sched(h)['n'] as int?) ?? 1).clamp(1, 31);

  /// Days done in the week or month starting at [p].
  static int periodCount(Map<String, dynamic> h, DateTime p) {
    var c = 0;
    final end = nextPeriod(h, p);
    for (var d = p; d.isBefore(end); d = _plus(d, 1)) {
      if (done(h, d)) c++;
    }
    return c;
  }

  // ---------- history ----------

  /// Every slot from the start up to [now], oldest first: each scheduled day, or each week/month.
  /// The current day or period is 'pending' until it is done (a day still in progress is not a miss).
  static List<(DateTime, Slot)> slots(Map<String, dynamic> h, DateTime now, {DateTime? from}) {
    final today = _d(now);
    var first = _d(start(h));
    if (from != null && from.isAfter(first)) first = _d(from);
    if (first.isBefore(DateTime(2000))) first = DateTime(2000);
    final out = <(DateTime, Slot)>[];
    if (byPeriod(h)) {
      final n = periodTarget(h);
      for (var p = periodStart(h, first); !p.isAfter(today); p = nextPeriod(h, p)) {
        final end = nextPeriod(h, p);
        // A period entirely paused does not count either way.
        var open = false;
        for (var d = p; d.isBefore(end); d = _plus(d, 1)) {
          if (!paused(h, d)) open = true;
        }
        if (!open) continue;
        final current = !today.isBefore(p) && today.isBefore(end);
        final count = periodCount(h, p);
        out.add((p, count >= n ? Slot.done : (current ? Slot.pending : Slot.missed)));
      }
      return out;
    }
    for (var d = first; !d.isAfter(today); d = _plus(d, 1)) {
      if (!scheduled(h, d)) continue;
      final Slot s;
      if (skipped(h, d)) {
        s = Slot.skipped;
      } else if (done(h, d)) {
        s = Slot.done;
      } else {
        s = d == today ? Slot.pending : Slot.missed;
      }
      out.add((d, s));
    }
    return out;
  }

  /// Current streak: done slots counting back from now. Rest days pass, and up to 'grace' misses in a row
  /// are forgiven (they do not add to the streak, but do not end it).
  static int currentStreak(Map<String, dynamic> h, DateTime now) {
    final grace = (h['grace'] as int?) ?? 0;
    var streak = 0, misses = 0;
    for (final (_, s) in slots(h, now).reversed) {
      switch (s) {
        case Slot.pending:
        case Slot.skipped:
          continue;
        case Slot.done:
          streak++;
          misses = 0;
        case Slot.missed:
          misses++;
          if (misses > grace) return streak;
      }
    }
    return streak;
  }

  static int longestStreak(Map<String, dynamic> h, DateTime now) {
    final grace = (h['grace'] as int?) ?? 0;
    var best = 0, run = 0, misses = 0;
    for (final (_, s) in slots(h, now)) {
      switch (s) {
        case Slot.pending:
        case Slot.skipped:
          continue;
        case Slot.done:
          run++;
          misses = 0;
          if (run > best) best = run;
        case Slot.missed:
          misses++;
          if (misses > grace) {
            run = 0;
            misses = 0;
          }
      }
    }
    return best;
  }

  /// 'day', 'week' or 'month': what one streak step is.
  static String unit(Map<String, dynamic> h) => byPeriod(h) ? kind(h) : 'day';

  /// Done share of the slots that counted in a range (rest days and today-in-progress left out). Null if none.
  static double? rate(Map<String, dynamic> h, DateTime from, DateTime to) {
    var done = 0, total = 0;
    for (final (_, s) in slots(h, to, from: from)) {
      if (s == Slot.done) {
        done++;
        total++;
      } else if (s == Slot.missed) {
        total++;
      }
    }
    return total == 0 ? null : done / total;
  }

  /// Consistency, 0 to 100: how reliably it was done over the last 30 days (90 for monthly targets).
  static int consistency(Map<String, dynamic> h, DateTime now) {
    final r = rate(h, _plus(now, kind(h) == 'month' ? -90 : -29), now);
    return r == null ? 0 : (r * 100).round();
  }

  static int missedCount(Map<String, dynamic> h, DateTime now, {DateTime? from}) =>
      slots(h, now, from: from).where((s) => s.$2 == Slot.missed).length;

  /// Days on which it was done, all time.
  static int totalDone(Map<String, dynamic> h) =>
      (h['logs'] as Map).keys.cast<String>().where((k) => done(h, pd(k))).length;

  /// Sum of logged amounts in a range (for numeric habits).
  static num totalValue(Map<String, dynamic> h, DateTime from, DateTime to) {
    num sum = 0;
    for (final e in (h['logs'] as Map).entries) {
      final k = e.key as String;
      if (k.compareTo(dk(from)) < 0 || k.compareTo(dk(to)) > 0) continue;
      final v = e.value is Map ? (e.value as Map)['v'] : null;
      if (v is num) sum += v;
    }
    return sum;
  }

  static const milestones = [1, 7, 21, 30, 50, 66, 100, 150, 200, 365, 500, 1000];

  /// Milestones reached (total days done), and the next one to aim for.
  static (List<int>, int?) milestonesOf(Map<String, dynamic> h) {
    final total = totalDone(h);
    return (milestones.where((m) => total >= m).toList(), milestones.where((m) => total < m).firstOrNull);
  }

  // ---------- today ----------

  /// Still to do today: scheduled, not done, not marked missed or skipped, and for weekly/monthly
  /// targets, the period's target not yet reached.
  static bool dueToday(Map<String, dynamic> h, DateTime now) {
    if (h['archived'] == true || !scheduled(h, now)) return false;
    final e = entry(h, dk(now));
    if (e != null && (e['skip'] == true || e['miss'] == true)) return false;
    if (done(h, now)) return false;
    if (byPeriod(h)) return periodCount(h, periodStart(h, now)) < periodTarget(h);
    return true;
  }

  /// Shown on today's list: due, or already done/started today (so you see the tick).
  static bool onToday(Map<String, dynamic> h, DateTime now) =>
      h['archived'] != true && scheduled(h, now) && (dueToday(h, now) || entry(h, dk(now)) != null);

  /// Today's overall progress across habits on today's list, 0 to 1. Null if none.
  static double? dayProgress(List<Map<String, dynamic>> habits, DateTime now) {
    final today = habits.where((h) => onToday(h, now) && !skipped(h, now)).toList();
    if (today.isEmpty) return null;
    return today.fold<double>(0, (a, h) => a + (progress(h, now) ?? 0)) / today.length;
  }

  /// The next habit in a stack after [h] (the one whose 'after' is h), if it is still due today.
  static Map<String, dynamic>? nextInStack(List<Map<String, dynamic>> habits, Map<String, dynamic> h, DateTime now) =>
      habits.where((x) => x['after'] == h['id'] && dueToday(x, now)).firstOrNull;
}
