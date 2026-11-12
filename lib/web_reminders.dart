import 'habit_core.dart';
import 'store.dart';
import 'web_notify.dart';

/// On the web app, shows a browser notification when a task, event or alarm is due, and at a habit's
/// reminder time, while Jarvis is open in a tab. Called every minute.
class WebReminders {
  static int? _last;

  /// What is due in (from, to]: titles and a line of detail. Pure, for tests.
  static List<(String, String)> due(Store s, DateTime from, DateTime to) {
    final out = <(String, String)>[];
    final a = from.millisecondsSinceEpoch, b = to.millisecondsSinceEpoch;
    for (final i in s.list('items')) {
      final w = i['when'] as int?;
      if (w == null || i['status'] != 'open' || i['allDay'] == true || w <= a || w > b) continue;
      out.add(('${i['title']}', i['kind'] == 'event' ? 'Starting now' : (i['kind'] == 'alarm' ? 'Alarm' : 'Due now')));
    }
    final today = DateTime(to.year, to.month, to.day);
    for (final h in s.list('habits')) {
      final r = h['remind'] as String?;
      if (r == null || h['archived'] == true) continue;
      final p = r.split(':');
      final at = DateTime(to.year, to.month, to.day, int.parse(p[0]), int.parse(p[1])).millisecondsSinceEpoch;
      if (at <= a || at > b || !HabitCore.scheduled(h, today) || HabitCore.done(h, today)) continue;
      out.add(('${h['name']}', 'Time for your habit'));
    }
    return out;
  }

  static void check(Store s) {
    if (webNotifyPermission() != 'granted') return;
    final now = DateTime.now();
    final from = _last == null ? now.subtract(const Duration(minutes: 1)) : DateTime.fromMillisecondsSinceEpoch(_last!);
    _last = now.millisecondsSinceEpoch;
    for (final (title, body) in due(s, from, now)) {
      webNotify(title, body);
    }
  }
}
