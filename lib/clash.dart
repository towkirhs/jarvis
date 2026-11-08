/// Events that overlap, and reminders before an event. Pure Dart, tested on its own.
class Clash {
  /// How long an event lasts when no duration was given.
  static const defaultMinutes = 60;

  /// Open timed events that overlap the slot starting at [start] (ms) and lasting [minutes].
  /// All-day items, tasks and alarms never clash: only events that hold your time. Touching ends do not clash.
  static List<Map<String, dynamic>> find(List<Map<String, dynamic>> items, int start, int minutes, {int? excludeId}) {
    final end = start + minutes * 60000;
    return [
      for (final i in items)
        if (i['kind'] == 'event' &&
            i['status'] == 'open' &&
            i['allDay'] != true &&
            i['when'] is int &&
            i['id'] != excludeId &&
            (i['when'] as int) < end &&
            start < (i['when'] as int) + ((i['dur'] as int?) ?? defaultMinutes) * 60000)
          i,
    ]..sort((a, b) => (a['when'] as int).compareTo(b['when'] as int));
  }

  /// "Physics class (9:00 am to 11:00 am)", for a message.
  static String label(Map<String, dynamic> i, String Function(int ms) clock) {
    final start = i['when'] as int;
    final end = start + ((i['dur'] as int?) ?? defaultMinutes) * 60000;
    return '${i['title']} (${clock(start)} to ${clock(end)})';
  }

  /// "Clashes with A (…) and B (…)", or '' if there is none.
  static String sentence(List<Map<String, dynamic>> clashes, String Function(int ms) clock) {
    if (clashes.isEmpty) return '';
    final names = [for (final c in clashes.take(2)) label(c, clock)];
    final more = clashes.length > 2 ? ' and ${clashes.length - 2} more' : '';
    return 'Clashes with ${names.join(' and ')}$more';
  }
}

/// Reminders a while before an item, on top of the one at its time.
class Lead {
  /// Minutes before, as offered: 0 is "at the time" (no extra reminder).
  static const options = [0, 5, 10, 15, 30, 60, 120, 1440];

  /// Notification ids for these reminders start here, clear of an item's own id.
  static const idBase = 1200000000;
  static int id(int nid) => idBase + nid;

  static String name(int m) => switch (m) {
        0 => 'At the time',
        60 => '1 hour before',
        120 => '2 hours before',
        1440 => '1 day before',
        _ => '$m min before',
      };

  /// How the notification starts: "In 15 min", "In 1 hour", "Tomorrow".
  static String short(int m) => switch (m) {
        60 => 'In 1 hour',
        120 => 'In 2 hours',
        1440 => 'Tomorrow',
        _ => 'In $m min',
      };

  /// What a new event gets unless you choose: Settings, "Remind before events".
  static int defaultFor(Map<String, dynamic> settings) => (settings['lead'] as num?)?.toInt() ?? 10;
}
