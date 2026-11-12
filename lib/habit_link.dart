/// Lets the calendar fill in habits. A habit with `link: ['tuition']` counts every finished event, and every
/// done task, whose title has one of those words. What it logs depends on the habit:
/// minutes for duration and limit habits, how many for count habits, the end time for "by a time" habits
/// (the end of sleep is when you got up), and "done" for the rest.
/// Calendar logs carry `cal: true`. Anything you log yourself is never touched.
class HabitLink {
  /// How far back the calendar is read.
  static const days = 14;

  static bool matches(String title, List words) {
    final t = title.toLowerCase();
    return words.any((w) {
      final s = '$w'.trim().toLowerCase();
      return s.isNotEmpty && RegExp('(^|[^a-z0-9])${RegExp.escape(s)}([^a-z0-9]|\$)').hasMatch(t);
    });
  }

  static String _day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// The day logs the calendar gives [habit] over the last [days] days, by 'YYYY-MM-DD'.
  static Map<String, Map<String, dynamic>> compute(Map<String, dynamic> habit, Iterable<Map<String, dynamic>> items, DateTime now) {
    final words = (habit['link'] as List?) ?? const [];
    if (words.isEmpty) return {};
    final from = DateTime(now.year, now.month, now.day - days);
    final minutes = <String, int>{};
    final count = <String, int>{};
    final ends = <String, DateTime>{};
    for (final i in items) {
      if (!matches('${i['title'] ?? ''}', words)) continue;
      DateTime? end;
      int mins;
      if (i['kind'] == 'task') {
        if (i['status'] != 'done' || i['doneAt'] is! int) continue;
        end = DateTime.fromMillisecondsSinceEpoch(i['doneAt'] as int);
        mins = (i['actual'] as int?) ?? (i['est'] as int?) ?? 0;
      } else if (i['kind'] == 'event') {
        if (i['status'] == 'cancelled' || i['when'] is! int || i['allDay'] == true) continue;
        mins = (i['dur'] as int?) ?? 60;
        end = DateTime.fromMillisecondsSinceEpoch(i['when'] as int).add(Duration(minutes: mins));
      } else {
        continue;
      }
      if (end.isAfter(now) || end.isBefore(from)) continue;
      final d = _day(end);
      minutes[d] = (minutes[d] ?? 0) + mins;
      count[d] = (count[d] ?? 0) + 1;
      if (ends[d] == null || end.isBefore(ends[d]!)) ends[d] = end;
    }
    final type = (habit['type'] as String?) ?? 'yesno';
    return {
      for (final d in count.keys)
        d: switch (type) {
          'duration' || 'limit' => {'v': minutes[d], 'cal': true},
          'count' || 'frequency' => {'v': count[d], 'cal': true},
          'time' => {'at': _hm(ends[d]!), 'cal': true},
          'yesno' => {'v': 1, 'cal': true},
          _ => {'done': true, 'cal': true},
        },
    };
  }

  /// Writes [found] into [logs]: fills days you have not logged, updates earlier calendar logs, and clears
  /// calendar logs in the window that no event backs any more. Returns whether anything changed.
  static bool apply(Map<String, dynamic> logs, Map<String, Map<String, dynamic>> found, DateTime now) {
    var changed = false;
    final from = _day(DateTime(now.year, now.month, now.day - days));
    for (final e in logs.entries.toList()) {
      final v = e.value;
      if (v is Map && v['cal'] == true && e.key.compareTo(from) >= 0 && !found.containsKey(e.key)) {
        logs.remove(e.key);
        changed = true;
      }
    }
    for (final e in found.entries) {
      final old = logs[e.key];
      if (old != null && !(old is Map && old['cal'] == true)) continue;
      if (old is Map && _same(old, e.value)) continue;
      logs[e.key] = e.value;
      changed = true;
    }
    return changed;
  }

  static bool _same(Map a, Map b) => a.length == b.length && a.keys.every((k) => a[k] == b[k]);
}
