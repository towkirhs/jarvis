/// The productivity engine's rules, pure Dart and tested:
/// Eisenhower (priority) decides what matters, Pareto (`vital`) what gives the most, time blocking when,
/// deep work how, active recall how to learn, and GTD (Inbox, Next, Waiting, Someday, weekly review) keeps it clear.

/// Active recall with Leitner boxes: a card you get right waits longer each time; a miss starts it over.
/// A card is `{deck, q, a, box, due}`.
class Recall {
  /// Days until the next review for a card in each box.
  static const gaps = [1, 2, 4, 8, 16, 32, 64];

  static ({int box, int due}) review(int box, bool gotIt, DateTime now) {
    final next = gotIt ? (box + 1).clamp(0, gaps.length - 1) : 0;
    final day = DateTime(now.year, now.month, now.day + gaps[next]);
    return (box: next, due: day.millisecondsSinceEpoch);
  }

  static bool isDue(Map<String, dynamic> card, DateTime now) =>
      ((card['due'] as int?) ?? 0) < DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
}

/// The 80/20 rule: about one open task in five should be marked vital.
class Pareto {
  static int target(int open) => (open * 0.2).ceil();
}

/// GTD lists beside the Inbox, and the weekly review.
class Gtd {
  static const lists = ['Next', 'Waiting', 'Someday'];

  static bool reviewDue(int? last, DateTime now) =>
      last == null || now.difference(DateTime.fromMillisecondsSinceEpoch(last)).inDays >= 7;
}

class Engine {
  static const _never = 8640000000000000;

  /// The one task to do now: the Eisenhower box first (High priority = urgent and important),
  /// then vital (Pareto) ones, then the sooner deadline. Waiting and Someday tasks are not for now.
  static Map<String, dynamic>? topTask(Iterable<Map<String, dynamic>> items) {
    final open = items
        .where((i) => i['kind'] == 'task' && i['status'] == 'open' && i['list'] != 'Waiting' && i['list'] != 'Someday')
        .toList();
    if (open.isEmpty) return null;
    open.sort((a, b) {
      final p = ((b['priority'] as int?) ?? 0).compareTo((a['priority'] as int?) ?? 0);
      if (p != 0) return p;
      final v = (b['vital'] == true ? 1 : 0).compareTo(a['vital'] == true ? 1 : 0);
      if (v != 0) return v;
      return ((a['when'] as int?) ?? _never).compareTo((b['when'] as int?) ?? _never);
    });
    return open.first;
  }

  static DateTime weekStart(DateTime now) => DateTime(now.year, now.month, now.day - (now.weekday - 1));

  static int deepMinutesThisWeek(Iterable<Map<String, dynamic>> focus, DateTime now) {
    final from = weekStart(now).millisecondsSinceEpoch;
    return focus.where((f) => f['deep'] == true && (f['start'] as int) >= from).fold<int>(0, (a, f) => a + (f['minutes'] as int));
  }
}
