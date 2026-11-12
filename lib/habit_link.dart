import 'habit_core.dart';

/// Lets the calendar fill in habits. A habit with `link: ['tuition']` counts every finished event, and every
/// done task, whose title has one of those words. What it logs depends on the habit:
/// minutes for duration and limit habits, how many for count habits, the end time for "by a time" habits
/// (the end of sleep is when you got up), and "done" for the rest.
/// A task Plan my day made for the habit (`planHabit`) counts when it is done, with or without words.
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
    final from = DateTime(now.year, now.month, now.day - days);
    final minutes = <String, int>{};
    final count = <String, int>{};
    final ends = <String, DateTime>{};
    for (final i in items) {
      if (i['habitId'] != null && i['habitId'] == habit['id']) continue; // a block this habit made itself
      // A task Plan my day made for this habit always counts; anything else counts by its title.
      if (i['planHabit'] != habit['id'] && !matches('${i['title'] ?? ''}', words)) continue;
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

  /// The calendar block for a day you ticked yourself, or null when the day is not done, was filled in by
  /// the calendar, or the habit is a limit (staying under something is not a block of time).
  /// Today's block ends now; a past day's starts at 8 pm; a "by a time" habit ends at the logged time.
  static ({DateTime start, int minutes})? block(Map<String, dynamic> habit, String day, Object? log, DateTime now) {
    if (log is Map && log['cal'] == true) return null;
    final type = (habit['type'] as String?) ?? 'yesno';
    if (type == 'limit') return null;
    final d = DateTime.parse(day);
    final e = log is Map ? log : const {};
    final partDuration = type == 'duration' && e['v'] is num && (e['v'] as num) > 0 && e['skip'] != true;
    if (!partDuration && !HabitCore.done({...habit, 'logs': {day: log}}, d)) return null;
    final minutes = type == 'duration' && e['v'] is num ? (e['v'] as num).round().clamp(5, 24 * 60) : 30;
    final at = e['at'] as String?;
    final DateTime end;
    if (type == 'time' && at != null) {
      final p = at.split(':');
      end = DateTime(d.year, d.month, d.day, int.parse(p[0]), int.parse(p[1]));
    } else if (_day(now) == day) {
      end = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    } else {
      return (start: DateTime(d.year, d.month, d.day, 20), minutes: minutes);
    }
    return (start: end.subtract(Duration(minutes: minutes)), minutes: minutes);
  }
}
