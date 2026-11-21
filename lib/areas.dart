import 'dart:math';

import 'day_log.dart';
import 'store.dart' show Rec;

/// Your Life map: the areas of your life (collection `areas` {name, words, x, y, status, note}) on a target.
/// `x`, `y` run 0..1 across the board: the left half is life, the right half work; the middle is this
/// season's focus and the edge is maintenance. Nothing is ranked: two areas can both sit in the middle.
///
/// Everything else finds its area here: a record's own `area` (an area id) wins, otherwise the area whose
/// words (or name) are in its title or text. Planning, Your day, the weekly check and the AI all use [of].
class Areas {
  static const statuses = {'good': 'Going well', 'ok': 'So-so', 'bad': 'Needs care'};
  static const zones = {'focus': 'Main focus', 'side': 'Side quest', 'maintenance': 'Maintenance'};

  /// How far from the middle, 0 (centre) to 1 (edge).
  static double distance(Rec a) {
    final x = ((a['x'] as num?) ?? 0.5).toDouble() - 0.5;
    final y = ((a['y'] as num?) ?? 0.5).toDouble() - 0.5;
    return min(1.0, sqrt(x * x + y * y) / 0.5);
  }

  /// 100 in the middle down to 10 at the edge.
  static int focus(Rec a) => (100 - distance(a) * 90).round();

  static String zone(Rec a) {
    final d = distance(a);
    return d < 0.34 ? 'focus' : (d < 0.67 ? 'side' : 'maintenance');
  }

  static bool isWork(Rec a) => ((a['x'] as num?) ?? 0.5) >= 0.5;

  /// Where an area goes when it is moved to [zone] (and [work] side), keeping its direction if it has one.
  static ({double x, double y}) place(Rec a, String zone, {bool? work}) {
    final r = switch (zone) { 'focus' => 0.08, 'side' => 0.25, _ => 0.4 };
    var dx = ((a['x'] as num?) ?? 0.5).toDouble() - 0.5;
    var dy = ((a['y'] as num?) ?? 0.5).toDouble() - 0.5;
    final w = work ?? isWork(a);
    if (dx.abs() < 0.01 || (dx >= 0) != w) dx = w ? 0.1 : -0.1;
    if (dx.abs() < 0.01 && dy.abs() < 0.01) dy = 0;
    final len = sqrt(dx * dx + dy * dy);
    return (x: 0.5 + dx / len * r, y: 0.5 + dy / len * r);
  }

  static List<String> words(Rec a) => [
        '${a['name'] ?? ''}'.toLowerCase().trim(),
        for (final w in (a['words'] as List?) ?? const []) '$w'.toLowerCase().trim(),
      ].where((w) => w.length >= 2).toList();

  static String _norm(String s) => ' ${s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ঀ-৿]+'), ' ').trim()} ';

  /// Whether [text] holds [word]: as a whole word or phrase, or as the start of a word ("gym" in "gyms").
  static bool _has(String text, String word) {
    final w = _norm(word).trim();
    if (w.isEmpty) return false;
    return text.contains(' $w ') || (w.length >= 3 && text.contains(' $w'));
  }

  /// The text a record is known by: a task's title, a habit's name, a log line, a payment's note and category.
  static String textOf(Rec r) =>
      [r['title'], r['name'], r['text'], r['note'], r['cat'], r['category'], r['desc']].whereType<String>().join(' ');

  /// The area of a record, or null.
  static Rec? of(List<Rec> areas, Rec r) {
    final own = r['area'];
    if (own is int) {
      final a = areas.where((a) => a['id'] == own).firstOrNull;
      if (a != null) return a;
    }
    return ofText(areas, textOf(r));
  }

  /// The area whose words are in [text]; the longest matching word wins ("phone bill" over "phone").
  static Rec? ofText(List<Rec> areas, String text) {
    final t = _norm(text);
    Rec? best;
    var len = 0;
    for (final a in areas) {
      for (final w in words(a)) {
        if (w.length > len && _has(t, w)) {
          best = a;
          len = w.length;
        }
      }
    }
    return best;
  }

  /// The area named [name] (any case), or null.
  static Rec? named(List<Rec> areas, String name) {
    final n = name.toLowerCase().trim();
    return areas.where((a) => '${a['name']}'.toLowerCase().trim() == n).firstOrNull;
  }

  /// Focus for each piece of a plan (task id, or minus a habit's id), from its area.
  static Map<int, int> focusOf(List<Rec> areas, List<Rec> pieces, {List<Rec> habits = const []}) {
    if (areas.isEmpty) return const {};
    final out = <int, int>{};
    for (final p in pieces) {
      final id = p['id'];
      if (id is! int) continue;
      final h = id < 0 ? habits.where((h) => h['id'] == -id).firstOrNull : null;
      final a = of(areas, h ?? p);
      if (a != null) out[id] = focus(a);
    }
    return out;
  }

  /// Minutes per area id (0 = no area) in [from]..[to]: what Your day shows you did (your notes, buttons,
  /// check-ins, app time) and finished tasks with a real length that Your day does not already hold. Sleep is left out.
  static Map<int, int> minutes(List<Rec> areas,
      {required List<Rec> log, required List<Rec> items, required DateTime from, required DateTime to, required DateTime now, List<AppSession> apps = const []}) {
    final out = <int, int>{};
    final f = from.millisecondsSinceEpoch, t = to.millisecondsSinceEpoch;
    void add(Rec? a, int start, int end) {
      final s = max(start, f), e = min(end, t);
      if (e <= s) return;
      final k = (a?['id'] as int?) ?? 0;
      out[k] = (out[k] ?? 0) + ((e - s) / 60000).round();
    }

    final seen = <String>{};
    for (final b in DayLog.blocks(log, from, to, now: now, apps: apps)) {
      if (b.kind == 'sleep') continue;
      seen.add(b.title.toLowerCase().trim());
      add(b.log == null ? ofText(areas, b.title) : of(areas, {...b.log!, 'title': b.title}), b.start, b.end);
    }
    for (final i in items) {
      final done = i['doneAt'];
      final actual = i['actual'];
      if (i['status'] != 'done' || done is! int || actual is! int || done < f || done >= t) continue;
      if (seen.contains('${i['title']}'.toLowerCase().trim())) continue;
      add(of(areas, i), done - actual * 60000, done);
    }
    return out;
  }

  /// What the week says about the map: a centre area that got little time, a maintenance area that took
  /// a lot, and an area that got nothing for three weeks. [week] and [threeWeeks] are from [minutes].
  static List<String> notes(List<Rec> areas, Map<int, int> week, Map<int, int> threeWeeks) {
    final total = week.values.fold<int>(0, (a, b) => a + b);
    final out = <String>[];
    for (final a in areas) {
      final m = week[a['id']] ?? 0;
      final z = zone(a);
      if (z == 'focus' && m < 120) {
        out.add('${a['name']} is in your centre but got ${hm(m)} this week.');
      } else if (z == 'maintenance' && total > 0 && m > total * 0.3) {
        out.add('${a['name']} is on maintenance but took ${hm(m)}, ${(m * 100 / total).round()}% of your logged time.');
      } else if ((threeWeeks[a['id']] ?? 0) == 0 && z != 'focus') {
        out.add('${a['name']} got no time for 3 weeks. Keep it where it is?');
      }
    }
    return out;
  }

  static String hm(int m) => m < 60 ? '${m}m' : (m % 60 == 0 ? '${m ~/ 60}h' : '${m ~/ 60}h ${m % 60}m');

  /// One line per area for the AI, centre first.
  static String forAi(List<Rec> areas, Map<int, int> week) {
    if (areas.isEmpty) return '';
    final sorted = [...areas]..sort((a, b) => focus(b).compareTo(focus(a)));
    return 'Life map (their priorities this season; focus 100 = centre, 10 = maintenance; hours logged this week):\n'
        '${sorted.map((a) => '- ${a['name']}: ${isWork(a) ? 'work' : 'life'}, ${zones[zone(a)]} (focus ${focus(a)})'
            '${a['status'] == null ? '' : ', ${statuses[a['status']]}'}, ${hm(week[a['id']] ?? 0)} this week'
            '${(a['note'] as String?)?.isNotEmpty ?? false ? ', note: ${a['note']}' : ''}').join('\n')}';
  }

  /// A starting set, so the map is not empty on the first day.
  static List<Rec> starters() => [
        {'name': 'Health', 'words': ['gym', 'walk', 'run', 'workout', 'doctor', 'medicine', 'sleep early'], 'x': 0.3, 'y': 0.35},
        {'name': 'Family', 'words': ['wife', 'ammu', 'abbu', 'family', 'home'], 'x': 0.25, 'y': 0.6},
        {'name': 'Friends', 'words': ['friend', 'friends', 'hangout'], 'x': 0.12, 'y': 0.5},
        {'name': 'Work', 'words': ['work', 'office', 'meeting', 'client'], 'x': 0.72, 'y': 0.4},
        {'name': 'Money', 'words': ['money', 'bill', 'budget', 'save', 'bank', 'bkash'], 'x': 0.8, 'y': 0.62},
        {'name': 'Rent', 'words': ['rent', 'tenant', 'meter', 'room'], 'x': 0.88, 'y': 0.45},
        {'name': 'Learning', 'words': ['study', 'read', 'course', 'class', 'flashcards'], 'x': 0.4, 'y': 0.8},
      ];
}
