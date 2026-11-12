import 'cal_index.dart';
import 'store.dart';

/// Changes to the calendar made by hand on the grid: move, resize, skip one date of a repeat.
class CalEdit {
  /// What a one-off copy of a repeating item carries over from it.
  static const carried = [
    'desc', 'priority', 'tags', 'list', 'lead', 'dur', 'allDay', 'place', 'placeWhen', 'color', 'location', 'span', 'vital', 'cat',
  ];

  /// The fields for a one-off copy of [master]: its details, but no repeat.
  static Rec oneOffFields(Rec master) => {
        for (final k in carried)
          if (master.containsKey(k)) k: master[k],
        'repeat': null,
      };

  /// The skip list of [master] with [day] added, once, in date order.
  static List<String> skipped(Rec master, String day) =>
      ({for (final k in (master['skip'] as List?) ?? const []) '$k', day}.toList()..sort());

  /// Minutes an item takes on the grid: a duration, else an estimate, else an hour (at least 15 minutes).
  static int minutes(Rec it) {
    final m = ((it['dur'] ?? it['est'] ?? 60) as num).round();
    return m < 15 ? 15 : (m > 1440 ? 1440 : m);
  }

  /// Skips one date of a repeating item. Returns the log id so the caller can offer Undo.
  static Future<int> skipDate(Store s, CalEntry e) async {
    final it = e.item;
    await s.updateRec('items', it, 'Skipped ${dayKey(e.start)}: ${it['title']}', (r) => r['skip'] = skipped(r, dayKey(e.start)));
    return _lastAction(s);
  }

  /// Takes one date out of a repeat and makes a one-off copy of it at [when] (the same time if null).
  static Future<({Rec copy, int log})> detach(Store s, CalEntry e, {int? when}) async {
    final it = e.item;
    final old = copyRec(it);
    it['skip'] = skipped(it, dayKey(e.start));
    await s.syncRecord('items', it);
    final undo = <Rec>[];
    final copy = await s.addItem(
      kind: it['kind'] as String,
      title: it['title'] as String,
      when: when ?? e.start.millisecondsSinceEpoch,
      est: it['kind'] == 'task' ? it['est'] as int? : null,
      undo: undo,
      extra: oneOffFields(it),
    );
    final id = s.logAction('Changed one date: ${it['title']}', [
      ...undo,
      {'op': 'put', 'col': 'items', 'rec': old},
    ]);
    s.save();
    return (copy: copy, log: id);
  }

  /// Moves one occurrence to [when]. A repeating item moves only that date.
  static Future<int> move(Store s, CalEntry e, int when) async {
    final it = e.item;
    if (it['repeat'] != null) return (await detach(s, e, when: when)).log;
    await s.updateRec('items', it, 'Moved: ${it['title']}', (r) {
      r['when'] = when;
      r['nid'] ??= s.nextId();
    });
    return _lastAction(s);
  }

  /// Gives an item a new length. A repeating item changes for every date.
  static Future<int> resize(Store s, CalEntry e, int mins) async {
    final it = e.item;
    await s.updateRec('items', it, 'Changed length: ${it['title']}', (r) => r[r['kind'] == 'task' ? 'est' : 'dur'] = mins);
    return _lastAction(s);
  }

  static int _lastAction(Store s) => s.list('actions').last['id'] as int;
}
