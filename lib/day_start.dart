/// Where your day starts. Pure Dart: [Store] sets [DayStart.minutes]; store.dart exports this file.
library;

String _two(int n) => n.toString().padLeft(2, '0');
String _key(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

/// Where your day starts, in minutes after midnight: 300 with "Day starts at 5 am", else 0 (set by [Store]).
/// Everything that asks "which day is this?" goes through it, so 1 am can still count as yesterday.
class DayStart {
  static int minutes = 0;

  /// [t] on the day clock: its date is the day the moment belongs to.
  static DateTime of(DateTime t) => minutes == 0 ? t : t.subtract(Duration(minutes: minutes));
  static DateTime now() => of(DateTime.now());

  /// The day a moment belongs to.
  static String key(int ms) => _key(of(DateTime.fromMillisecondsSinceEpoch(ms)));
  static String today() => _key(now());

  /// The day an item belongs to: an all-day item keeps its date, a timed one follows the day start.
  static String? itemDay(Map i) {
    final w = i['when'];
    if (w is! int) return null;
    return i['allDay'] == true ? _key(DateTime.fromMillisecondsSinceEpoch(w)) : key(w);
  }

}
