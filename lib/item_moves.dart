import 'store.dart';

/// Moving a task or event: to another day, into a habit, or a copy of it. Each is one Activity entry with Undo.
class ItemMoves {
  /// The item as plain text: title, when, list and details.
  static String asText(Rec it) => [
        '${it['title']}',
        if (it['when'] is int) it['allDay'] == true ? niceDay(it['when'] as int) : niceWhen(it['when'] as int),
        if ((it['list'] as String?) != null && it['list'] != 'Inbox') 'List: ${it['list']}',
        if ('${it['desc'] ?? ''}'.trim().isNotEmpty) '${it['desc']}',
      ].join('\n');

  /// To [day], keeping its time of day (or all day). Its fixed place in a day's plan is let go.
  static Future<void> moveTo(Store s, Rec it, DateTime day) async {
    final w = it['when'] as int?;
    final t = w == null ? null : fromMs(w);
    final allDay = w == null || it['allDay'] == true;
    final to = DateTime(day.year, day.month, day.day, allDay ? 0 : t!.hour, allDay ? 0 : t!.minute).millisecondsSinceEpoch;
    await s.updateRec('items', it, 'Moved: ${it['title']}', (r) {
      r['when'] = to;
      if (w == null) r['allDay'] = true;
      r.remove('planned');
    });
  }

  /// A second, open item just like it (without its links, alarm or done state).
  static Future<Rec> duplicate(Store s, Rec it) async {
    final copy = copyRec(it)
      ..['id'] = s.nextId()
      ..['nid'] = it['when'] == null ? null : s.nextId()
      ..['status'] = 'open'
      ..['doneAt'] = null
      ..['startedAt'] = null
      ..['actual'] = null
      ..['captureId'] = null
      ..remove('clock')
      ..remove('planned')
      ..remove('partOf');
    s.list('items').add(copy);
    s.logAction('Copy made: ${it['title']}', [
      {'op': 'rm', 'col': 'items', 'id': copy['id'], 'nid': copy['nid']},
    ]);
    await s.syncRecord('items', copy);
    s.save();
    return copy;
  }

  /// A daily habit with the same name, and the task put away (cancelled). Undo brings the task back.
  static Future<Rec> toHabit(Store s, Rec it) async {
    final undo = <Rec>[];
    final w = it['when'] as int?;
    final remind = w == null || it['allDay'] == true ? null : '${two(fromMs(w).hour)}:${two(fromMs(w).minute)}';
    final h = await s.addHabit('${it['title']}', 7, remind: remind, undo: undo); // 7 a week: every day
    undo.add({'op': 'put', 'col': 'items', 'rec': copyRec(it)});
    it['status'] = 'cancelled';
    await s.syncRecord('items', it);
    s.logAction('Turned into a habit: ${it['title']}', undo);
    s.save();
    return h;
  }
}
