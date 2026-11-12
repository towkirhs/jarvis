import 'store.dart';

/// One item on one day of the calendar. A repeating item has an entry for every date, not just the next one.
class CalEntry {
  const CalEntry(this.item, this.start, {required this.repeated, required this.firstDay});

  /// The stored item. For a repeating one this is the item the repeat belongs to.
  final Rec item;

  /// When this date's occurrence starts (the stored time, moved to this date).
  final DateTime start;

  /// True for a date after the stored one.
  final bool repeated;

  /// False on the second and later days of a multi-day item.
  final bool firstDay;
}

/// Every view of the calendar reads items through this: one pass, grouped by day.
class CalIndex {
  /// A repeat is drawn at most this many times inside one window.
  static const maxPerItem = 400;

  /// Entries for the days from [from] to [to] (both included), by [dayKey]. Each day is sorted:
  /// all-day first, then by start time.
  static Map<String, List<CalEntry>> build(List<Rec> items, DateTime from, DateTime to) {
    final first = DateTime(from.year, from.month, from.day);
    final last = DateTime(to.year, to.month, to.day);
    final out = <String, List<CalEntry>>{};
    for (final it in items) {
      final w = it['when'];
      if (w is! int || it['status'] == 'cancelled') continue;
      final start = fromMs(w);
      final allDay = it['allDay'] == true;
      final span = allDay ? ((it['span'] as num?)?.toInt() ?? 1).clamp(1, 366).toInt() : 1;
      final repeat = _known(it['repeat']);
      final skip = {for (final k in (it['skip'] as List?) ?? const []) '$k'};
      var landed = 0;
      var n = repeat == null ? 0 : _firstWorth(start, repeat, first, span);
      for (var guard = 0; guard < maxPerItem * 5 && landed < maxPerItem; guard++, n++) {
        final at = _nth(start, repeat, n);
        final day = DateTime(at.year, at.month, at.day);
        if (day.isAfter(last)) break;
        if (skip.contains(dayKey(day))) {
          if (repeat == null) break;
          continue;
        }
        var added = false;
        for (var k = 0; k < span; k++) {
          final d = DateTime(day.year, day.month, day.day + k);
          if (d.isBefore(first) || d.isAfter(last)) continue;
          (out[dayKey(d)] ??= []).add(CalEntry(it, at, repeated: n > 0, firstDay: k == 0));
          added = true;
        }
        if (added) landed++;
        if (repeat == null) break;
      }
    }
    for (final list in out.values) {
      list.sort((a, b) {
        final aa = a.item['allDay'] == true ? 0 : 1;
        final bb = b.item['allDay'] == true ? 0 : 1;
        if (aa != bb) return aa - bb;
        final t = a.start.compareTo(b.start);
        return t != 0 ? t : (a.item['id'] as int).compareTo(b.item['id'] as int);
      });
    }
    return out;
  }

  /// Countdowns by the day they fall on next. Count-ups have no day.
  static Map<String, List<Rec>> countdowns(Store s) {
    final out = <String, List<Rec>>{};
    for (final c in s.list('countdowns')) {
      if (c['kind'] == 'countup') continue;
      (out[dayKey(s.countdownNext(c))] ??= []).add(c);
    }
    return out;
  }

  static String? _known(Object? r) => const {'daily', 'weekly', 'monthly', 'yearly'}.contains(r) ? r as String : null;

  /// The [n]th time of a repeat that starts at [start]; n = 0 is the start itself.
  /// A month or year that is too short for the start's day gets its last day.
  static DateTime _nth(DateTime start, String? repeat, int n) {
    if (n == 0 || repeat == null) return start;
    switch (repeat) {
      case 'daily':
        return DateTime(start.year, start.month, start.day + n, start.hour, start.minute);
      case 'weekly':
        return DateTime(start.year, start.month, start.day + 7 * n, start.hour, start.minute);
      case 'monthly':
        final total = start.month - 1 + n;
        return _clamped(start.year + total ~/ 12, total % 12 + 1, start);
      default:
        return _clamped(start.year + n, start.month, start);
    }
  }

  static DateTime _clamped(int year, int month, DateTime start) {
    final last = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, start.day < last ? start.day : last, start.hour, start.minute);
  }

  /// Where to begin counting so a repeat that started long ago does not loop its way up to the window.
  static int _firstWorth(DateTime start, String repeat, DateTime first, int span) {
    final a = DateTime.utc(start.year, start.month, start.day);
    final b = DateTime.utc(first.year, first.month, first.day);
    final days = b.difference(a).inDays - span;
    if (days <= 0) return 0;
    final n = switch (repeat) {
      'daily' => days,
      'weekly' => days ~/ 7,
      'monthly' => (first.year - start.year) * 12 + first.month - start.month - 1,
      _ => first.year - start.year - 1,
    };
    return n < 0 ? 0 : n;
  }
}
