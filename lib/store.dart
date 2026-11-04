import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native.dart';

typedef Rec = Map<String, dynamic>;

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime fromMs(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

Rec copyRec(Rec r) => jsonDecode(jsonEncode(r)) as Rec;

String two(int n) => n.toString().padLeft(2, '0');

String clock(int ms) {
  final d = fromMs(ms);
  return '${two(d.hour)}:${two(d.minute)}';
}

String niceWhen(int ms) {
  final d = fromMs(ms);
  final now = DateTime.now();
  final today = dayKey(now);
  final tomorrow = dayKey(DateTime(now.year, now.month, now.day + 1));
  final k = dayKey(d);
  final day = k == today ? 'Today' : (k == tomorrow ? 'Tomorrow' : k);
  return '$day ${clock(ms)}';
}

/// All app data lives in one JSON document in local storage. Collections hold plain maps.
class Store extends ChangeNotifier {
  late SharedPreferences _prefs;
  Rec _s = {};
  String apiKey = '';

  static const _collections = [
    'captures', 'items', 'habits', 'promises', 'decisions', 'inbox', 'actions', 'countdowns', 'focus',
  ];

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString('state');
    _s = raw == null ? <String, dynamic>{} : jsonDecode(raw) as Rec;
    _fillDefaults();
    apiKey = _prefs.getString('gemini_key') ?? '';
  }

  void _fillDefaults() {
    for (final c in _collections) {
      _s.putIfAbsent(c, () => <dynamic>[]);
    }
    _s.putIfAbsent('summaries', () => <String, dynamic>{});
    _s.putIfAbsent('boosts', () => <String, dynamic>{});
    _s.putIfAbsent('next', () => 100);
    // Habits used to have only a weekly target ('perWeek').
    for (final h in list('habits')) {
      h['times'] ??= h['perWeek'] ?? 3;
      h['per'] ??= 'week';
      h['color'] ??= 0;
    }
    _s.putIfAbsent(
      'settings',
      () => <String, dynamic>{'model': 'gemini-2.5-flash-lite', 'prefilter': true, 'cap': 6},
    );
  }

  List<Rec> list(String name) => (_s[name] as List).cast<Rec>();
  Rec get settings => _s['settings'] as Rec;
  Rec get summaries => _s['summaries'] as Rec;
  Rec get boosts => _s['boosts'] as Rec;
  int get cap => (settings['cap'] as int?) ?? 6;

  void save() {
    _prefs.setString('state', jsonEncode(_s));
    notifyListeners();
  }

  Future<void> setApiKey(String key) async {
    apiKey = key.trim();
    await _prefs.setString('gemini_key', apiKey);
    notifyListeners();
  }

  int nextId() {
    final n = _s['next'] as int;
    _s['next'] = n + 1;
    return n;
  }

  Rec? byId(String col, int? id) {
    for (final r in list(col)) {
      if (r['id'] == id) return r;
    }
    return null;
  }

  // ---------- reminders and the daily notification budget ----------

  /// How many quiet reminders are already planned for a day (two fixed ones plus tasks, promises, boosts).
  int noticeLoad(String day) {
    var n = 2;
    for (final it in list('items')) {
      final w = it['when'] as int?;
      if (it['kind'] == 'task' && it['status'] == 'open' && w != null && dayKey(fromMs(w)) == day) n++;
    }
    for (final p in list('promises')) {
      final w = p['remindAt'] as int?;
      if (p['status'] == 'open' && w != null && dayKey(fromMs(w)) == day) n++;
    }
    return n + ((boosts[day] as int?) ?? 0);
  }

  /// Makes the phone's alarm schedule match one item or promise.
  Future<void> syncRecord(String col, Rec r) async {
    if (col == 'habits') return _syncHabitReminder(r);
    if (col == 'countdowns') return _syncCountdown(r);
    final nid = r['nid'] as int?;
    if (nid == null) return;
    final at = col == 'items' ? r['when'] as int? : r['remindAt'] as int?;
    if (at == null || r['status'] != 'open' || at <= DateTime.now().millisecondsSinceEpoch) {
      await Native.cancel(nid);
      return;
    }
    final isAlarm = col == 'items' && r['kind'] != 'task';
    if (!isAlarm && noticeLoad(dayKey(fromMs(at))) > cap) {
      await Native.cancel(nid);
      return;
    }
    final label = col == 'items'
        ? (isAlarm ? r['title'] as String : 'Due: ${r['title']}')
        : 'Promise to ${r['person']}: ${r['what']}';
    await Native.schedule(id: nid, millis: at, kind: isAlarm ? 'alarm' : 'notice', label: label);
  }

  Future<void> ensureDaily() async {
    Future<void> daily(int id, int hour, int minute, String label) async {
      final now = DateTime.now();
      var t = DateTime(now.year, now.month, now.day, hour, minute);
      if (!t.isAfter(now)) t = DateTime(now.year, now.month, now.day + 1, hour, minute);
      await Native.schedule(
        id: id, millis: t.millisecondsSinceEpoch, kind: 'notice', label: label, repeatDaily: true,
      );
    }

    await daily(1, 7, 30, 'Morning plan is ready. Open Jarvis to see your day.');
    await daily(2, 21, 0, 'Evening check-in: log your habits and close out the day.');
  }

  /// A habit's optional daily reminder at 'remind' (HH:MM).
  Future<void> _syncHabitReminder(Rec h) async {
    final rid = h['rid'] as int?;
    if (rid == null) return;
    final t = h['remind'] as String?;
    if (t == null) {
      await Native.cancel(rid);
      return;
    }
    final hm = t.split(':');
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, int.parse(hm[0]), int.parse(hm[1]));
    if (!at.isAfter(now)) at = DateTime(now.year, now.month, now.day + 1, at.hour, at.minute);
    await Native.schedule(
      id: rid,
      millis: at.millisecondsSinceEpoch,
      kind: 'notice',
      label: 'Time for ${h['name']}',
      repeatDaily: true,
    );
  }

  /// A countdown reminds at 9:00 on its (next) day.
  Future<void> _syncCountdown(Rec c) async {
    final nid = c['nid'] as int?;
    if (nid == null) return;
    final day = countdownNext(c);
    final at = DateTime(day.year, day.month, day.day, 9);
    if (!at.isAfter(DateTime.now())) {
      await Native.cancel(nid);
      return;
    }
    await Native.schedule(id: nid, millis: at.millisecondsSinceEpoch, kind: 'notice', label: 'Today: ${c['title']}');
  }

  /// The countdown's date, or for a yearly one (birthday, anniversary) its next occurrence from today.
  DateTime countdownNext(Rec c) {
    final d = DateTime.parse(c['date'] as String);
    if (c['yearly'] != true) return d;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisYear = DateTime(now.year, d.month, d.day);
    return thisYear.isBefore(today) ? DateTime(now.year + 1, d.month, d.day) : thisYear;
  }

  Future<Rec> addCountdown(String title, String date, String kind, {List<Rec>? undo}) async {
    final c = <String, dynamic>{
      'id': nextId(),
      'title': title,
      'date': date,
      'kind': kind,
      'yearly': kind == 'birthday' || kind == 'anniversary',
      'nid': nextId(),
    };
    list('countdowns').add(c);
    undo?.add({'op': 'rm', 'col': 'countdowns', 'id': c['id'], 'nid': c['nid']});
    await syncRecord('countdowns', c);
    save();
    return c;
  }

  Future<void> resyncAll() async {
    for (final c in list('countdowns')) {
      await syncRecord('countdowns', c);
    }
    for (final h in list('habits')) {
      await syncRecord('habits', h);
    }
    for (final it in list('items')) {
      await syncRecord('items', it);
    }
    for (final p in list('promises')) {
      await syncRecord('promises', p);
    }
  }

  /// A short celebration reminder, only if today's budget still has room.
  Future<void> boost(String text) async {
    final day = dayKey(DateTime.now());
    if (noticeLoad(day) >= cap) return;
    boosts[day] = ((boosts[day] as int?) ?? 0) + 1;
    await Native.schedule(
      id: nextId(),
      millis: DateTime.now().millisecondsSinceEpoch + 2000,
      kind: 'notice',
      label: text,
    );
    save();
  }

  // ---------- activity log and undo ----------

  int logAction(String desc, List<Rec> undo) {
    final id = nextId();
    final a = list('actions');
    a.add({
      'id': id,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'desc': desc,
      'undo': undo,
      'undone': false,
    });
    while (a.length > 100) {
      a.removeAt(0);
    }
    return id;
  }

  Future<void> undo(int actionId) async {
    final a = byId('actions', actionId);
    if (a == null || a['undone'] == true) return;
    for (final op in (a['undo'] as List).cast<Rec>()) {
      final col = list(op['col'] as String);
      if (op['op'] == 'rm') {
        col.removeWhere((r) => r['id'] == op['id']);
        final nid = op['nid'] as int?;
        if (nid != null) await Native.cancel(nid);
      } else {
        final old = copyRec(op['rec'] as Rec);
        final i = col.indexWhere((r) => r['id'] == old['id']);
        if (i >= 0) {
          col[i] = old;
        } else {
          col.add(old);
        }
        if (op['col'] != 'actions') {
          await syncRecord(op['col'] as String, old);
        }
      }
    }
    a['undone'] = true;
    save();
  }

  /// Changes one record and logs an undoable action for it.
  Future<void> updateRec(String col, Rec r, String desc, void Function(Rec) mutate) async {
    final old = copyRec(r);
    mutate(r);
    await syncRecord(col, r);
    logAction(desc, [
      {'op': 'put', 'col': col, 'rec': old},
    ]);
    save();
  }

  void removeRec(String col, Rec r, String desc) {
    final old = copyRec(r);
    list(col).removeWhere((x) => x['id'] == r['id']);
    final rid = (col == 'habits' ? r['rid'] : r['nid']) as int?;
    if (rid != null) Native.cancel(rid);
    logAction(desc, [
      {'op': 'put', 'col': col, 'rec': old},
    ]);
    save();
  }

  // ---------- items, promises, decisions, inbox ----------

  Future<Rec> addItem({
    required String kind,
    required String title,
    int? when,
    int? est,
    String? cat,
    int? captureId,
    required List<Rec> undo,
    Rec extra = const {},
  }) async {
    final id = nextId();
    final nid = when != null ? nextId() : null;
    final it = <String, dynamic>{
      'id': id, 'kind': kind, 'title': title, 'when': when, 'status': 'open', 'nid': nid,
      'est': est, 'cat': cat, 'startedAt': null, 'doneAt': null, 'actual': null,
      'postponed': 0, 'captureId': captureId,
      'desc': null, 'priority': 0, 'tags': <String>[], 'list': 'Inbox', 'repeat': null, 'dur': null,
      ...extra,
    };
    list('items').add(it);
    undo.add({'op': 'rm', 'col': 'items', 'id': id, 'nid': nid});
    await syncRecord('items', it);
    return it;
  }

  Future<void> addPromise({
    required String person,
    required String what,
    int? due,
    required int captureId,
    required List<Rec> undo,
  }) async {
    final id = nextId();
    int? remindAt;
    if (due != null) {
      final d = fromMs(due);
      final dayBefore = DateTime(d.year, d.month, d.day - 1, 9).millisecondsSinceEpoch;
      final now = DateTime.now().millisecondsSinceEpoch;
      remindAt = dayBefore > now ? dayBefore : (due > now ? due : null);
    }
    final nid = remindAt != null ? nextId() : null;
    final p = <String, dynamic>{
      'id': id, 'person': person, 'what': what, 'due': due, 'status': 'open',
      'remindAt': remindAt, 'nid': nid, 'captureId': captureId,
    };
    list('promises').add(p);
    undo.add({'op': 'rm', 'col': 'promises', 'id': id, 'nid': nid});
    await syncRecord('promises', p);
  }

  void addDecision({
    required String decision,
    String? reason,
    required List<String> tags,
    required int captureId,
    required List<Rec> undo,
  }) {
    final id = nextId();
    list('decisions').add({
      'id': id, 'ts': DateTime.now().millisecondsSinceEpoch, 'decision': decision,
      'reason': reason, 'tags': tags, 'captureId': captureId,
    });
    undo.add({'op': 'rm', 'col': 'decisions', 'id': id});
  }

  void addInbox(Rec parsed, int captureId, String why, List<Rec> undo) {
    final id = nextId();
    list('inbox').add({'id': id, 'captureId': captureId, 'item': parsed, 'why': why});
    undo.add({'op': 'rm', 'col': 'inbox', 'id': id});
  }

  /// Past decisions that share a topic with the new note.
  List<Rec> relatedDecisions(List<String> topics, int exceptCaptureId) {
    final t = topics.map((e) => e.toLowerCase()).toSet();
    return list('decisions').where((d) {
      if (d['captureId'] == exceptCaptureId) return false;
      final tags = (d['tags'] as List).map((e) => e.toString().toLowerCase());
      return tags.any(t.contains);
    }).toList();
  }

  // ---------- items: done, start, estimates ----------

  /// The next time after [when] for a repeat of 'daily', 'weekly', 'monthly' or 'yearly', in the future.
  static int nextRepeat(int when, String repeat) {
    var d = fromMs(when);
    final now = DateTime.now();
    do {
      d = switch (repeat) {
        'daily' => DateTime(d.year, d.month, d.day + 1, d.hour, d.minute),
        'weekly' => DateTime(d.year, d.month, d.day + 7, d.hour, d.minute),
        'monthly' => DateTime(d.year, d.month + 1, d.day, d.hour, d.minute),
        _ => DateTime(d.year + 1, d.month, d.day, d.hour, d.minute),
      };
    } while (!d.isAfter(now));
    return d.millisecondsSinceEpoch;
  }

  Future<void> markDone(Rec it) async {
    final when = it['when'] as int?;
    final repeat = it['repeat'] as String?;
    if (repeat != null && when != null) {
      // Keep a done copy for the record, and move the repeating item to its next time.
      final now = DateTime.now().millisecondsSinceEpoch;
      final done = copyRec(it)
        ..['id'] = nextId()
        ..['status'] = 'done'
        ..['doneAt'] = now
        ..['repeat'] = null
        ..['nid'] = null;
      final old = copyRec(it);
      list('items').add(done);
      it['when'] = nextRepeat(when, repeat);
      it['startedAt'] = null;
      await syncRecord('items', it);
      logAction('Done: ${it['title']} (next ${niceWhen(it['when'] as int)})', [
        {'op': 'rm', 'col': 'items', 'id': done['id']},
        {'op': 'put', 'col': 'items', 'rec': old},
      ]);
      save();
      await boost('Done: ${it['title']}');
      return;
    }
    await updateRec('items', it, 'Done: ${it['title']}', (r) {
      final now = DateTime.now().millisecondsSinceEpoch;
      r['status'] = 'done';
      r['doneAt'] = now;
      final started = r['startedAt'] as int?;
      if (started != null) {
        final minutes = ((now - started) / 60000).round();
        r['actual'] = minutes < 1 ? 1 : minutes;
      }
    });
    await boost('Done: ${it['title']}');
  }

  /// Suggests a longer or shorter estimate once five finished tasks in the category show a pattern.
  ({int est, double ratio})? estimateSuggestion(String? cat, int? est) {
    if (cat == null || est == null) return null;
    final ratios = <double>[];
    for (final it in list('items')) {
      final a = it['actual'] as int?;
      final e = it['est'] as int?;
      if (it['cat'] == cat && it['status'] == 'done' && a != null && e != null && e > 0) {
        ratios.add(a / e);
      }
    }
    if (ratios.length < 5) return null;
    ratios.sort();
    final r = ratios[ratios.length ~/ 2];
    if ((r - 1).abs() < 0.2) return null;
    return (est: (est * r).round(), ratio: r);
  }

  // ---------- habits ----------

  /// times per 'week' or 'month'; remind is an optional daily reminder time HH:MM.
  Future<Rec> addHabit(String name, int times, {String per = 'week', String? remind, List<Rec>? undo}) async {
    final h = <String, dynamic>{
      'id': nextId(),
      'name': name,
      'times': times,
      'per': per,
      'color': list('habits').length,
      'remind': remind,
      'rid': remind == null ? null : nextId(),
      'logs': <String, dynamic>{},
    };
    list('habits').add(h);
    undo?.add({'op': 'rm', 'col': 'habits', 'id': h['id'], 'nid': h['rid']});
    await syncRecord('habits', h);
    save();
    return h;
  }

  DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

  /// First day of the week or month (the habit's period) that contains d.
  DateTime periodStart(Rec h, DateTime d) =>
      h['per'] == 'month' ? DateTime(d.year, d.month, 1) : mondayOf(d);

  DateTime _nextPeriod(Rec h, DateTime start) => h['per'] == 'month'
      ? DateTime(start.year, start.month + 1, 1)
      : DateTime(start.year, start.month, start.day + 7);

  DateTime _prevPeriod(Rec h, DateTime start) => h['per'] == 'month'
      ? DateTime(start.year, start.month - 1, 1)
      : DateTime(start.year, start.month, start.day - 7);

  /// Times done in the period starting at start.
  int periodCount(Rec h, DateTime start) {
    final logs = h['logs'] as Rec;
    final end = _nextPeriod(h, start);
    var c = 0;
    for (var d = start; d.isBefore(end); d = DateTime(d.year, d.month, d.day + 1)) {
      if (logs[dayKey(d)] == 'yes') c++;
    }
    return c;
  }

  /// Consecutive weeks (or months) in which the habit reached its target.
  int streakPeriods(Rec h) {
    final target = h['times'] as int;
    final now = periodStart(h, DateTime.now());
    var streak = periodCount(h, now) >= target ? 1 : 0;
    var p = _prevPeriod(h, now);
    while (periodCount(h, p) >= target) {
      streak++;
      p = _prevPeriod(h, p);
    }
    return streak;
  }

  /// Habits still to do today: not logged today and target for this week/month not yet reached.
  List<Rec> habitsDueToday() {
    final now = DateTime.now();
    final today = dayKey(now);
    return list('habits')
        .where((h) =>
            (h['logs'] as Rec)[today] == null && periodCount(h, periodStart(h, now)) < (h['times'] as int))
        .toList();
  }

  /// value: 'yes', 'no' (said they skipped it), or null (clear the day).
  Future<void> logHabit(Rec h, String day, String? value) async {
    final before = streakPeriods(h);
    final old = copyRec(h);
    final logs = h['logs'] as Rec;
    if (value == null) {
      logs.remove(day);
    } else {
      logs[day] = value;
    }
    final verb = value == 'yes' ? 'Logged' : (value == 'no' ? 'Skipped' : 'Cleared');
    logAction('$verb ${h['name']} on $day', [
      {'op': 'put', 'col': 'habits', 'rec': old},
    ]);
    save();
    final after = streakPeriods(h);
    if (value == 'yes' && after > before) {
      await boost('${h['name']}: $after ${h['per']} streak');
    }
  }

  // ---------- focus (pomodoro and stopwatch) ----------

  /// The running focus session, or null. Kept in storage so it survives the app being closed.
  Rec? get focusActive => _s['focusActive'] as Rec?;

  /// mode 'pomo' counts down [minutes]; 'watch' counts up. A break is a pomo that is not recorded.
  Future<void> startFocus({required String mode, int minutes = 25, int? taskId, String label = 'Focus', bool isBreak = false}) async {
    final start = DateTime.now().millisecondsSinceEpoch;
    final f = <String, dynamic>{
      'mode': mode,
      'start': start,
      'minutes': minutes,
      'taskId': taskId,
      'label': label,
      'break': isBreak,
      'nid': nextId(),
    };
    _s['focusActive'] = f;
    if (mode == 'pomo') {
      await Native.schedule(
        id: f['nid'] as int,
        millis: start + minutes * 60000,
        kind: 'notice',
        label: isBreak ? 'Break is over' : 'Focus done: $label',
      );
    }
    save();
  }

  /// Ends the running session and records it (breaks and sessions under a minute are not kept).
  Future<void> stopFocus() async {
    final f = focusActive;
    if (f == null) return;
    _s['focusActive'] = null;
    await Native.cancel(f['nid'] as int);
    final start = f['start'] as int;
    var end = DateTime.now().millisecondsSinceEpoch;
    final planned = start + (f['minutes'] as int) * 60000;
    if (f['mode'] == 'pomo' && end > planned) end = planned;
    final minutes = ((end - start) / 60000).floor();
    if (f['break'] != true && minutes >= 1) {
      list('focus').add({
        'id': nextId(),
        'start': start,
        'end': end,
        'minutes': minutes,
        'mode': f['mode'],
        'pomo': f['mode'] == 'pomo' && end >= planned,
        'taskId': f['taskId'],
        'label': f['label'],
      });
    }
    save();
  }

  /// Finishes a pomodoro whose time is up. Called every second while the app is open.
  Future<void> checkFocus() async {
    final f = focusActive;
    if (f == null || f['mode'] != 'pomo') return;
    if (DateTime.now().millisecondsSinceEpoch >= (f['start'] as int) + (f['minutes'] as int) * 60000) {
      await stopFocus();
    }
  }

  // ---------- journal ----------

  List<Rec> capturesOn(String day) => list('captures')
      .where((c) => c['status'] == 'done' && dayKey(fromMs(c['ts'] as int)) == day)
      .toList();

  List<String> journalDays() {
    final days = <String>{};
    for (final c in list('captures')) {
      if (c['status'] == 'done') days.add(dayKey(fromMs(c['ts'] as int)));
    }
    return days.toList()..sort((a, b) => b.compareTo(a));
  }

  /// Notes written on today's month and day in earlier years.
  List<Rec> onThisDay() {
    final now = DateTime.now();
    return list('captures').where((c) {
      if (c['status'] != 'done') return false;
      final d = fromMs(c['ts'] as int);
      return d.year < now.year && d.month == now.month && d.day == now.day;
    }).toList();
  }

  // ---------- backup ----------

  String exportBackup() => jsonEncode(_s);

  Future<void> importBackup(String text) async {
    final data = jsonDecode(text) as Rec;
    if (data['items'] is! List || data['captures'] is! List) {
      throw const FormatException('Not a Jarvis backup');
    }
    _s = data;
    _fillDefaults();
    save();
    await resyncAll();
  }
}
