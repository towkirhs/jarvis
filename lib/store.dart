import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'categories.dart';
import 'clash.dart';
import 'habit_core.dart';
import 'native.dart';

typedef Rec = Map<String, dynamic>;

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime fromMs(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

Rec copyRec(Rec r) => jsonDecode(jsonEncode(r)) as Rec;

String two(int n) => n.toString().padLeft(2, '0');

const _shortDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// 16:30 -> "4:30 pm".
String clock(int ms) {
  final d = fromMs(ms);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${two(d.minute)} ${d.hour < 12 ? 'am' : 'pm'}';
}

/// 45 -> "45 min", 90 -> "1h 30m", 120 -> "2h".
String fmtMinutes(int m) => m < 60 ? '$m min' : '${m ~/ 60}h${m % 60 == 0 ? '' : ' ${m % 60}m'}';

/// "Today", "Tomorrow", "Yesterday", "Sat" within a week, otherwise "7 Nov" (with the year if not this year).
String niceDay(int ms) {
  final d = fromMs(ms);
  final now = DateTime.now();
  final diff = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  if (diff > 1 && diff < 7) return _shortDays[d.weekday - 1];
  return '${_shortDays[d.weekday - 1]} ${d.day} ${_shortMonths[d.month - 1]}${d.year == now.year ? '' : ' ${d.year}'}';
}

String niceWhen(int ms) => '${niceDay(ms)}, ${clock(ms)}';

/// All app data lives in one JSON document in local storage. Collections hold plain maps.
class Store extends ChangeNotifier {
  late SharedPreferences _prefs;
  Rec _s = {};
  String apiKey = '';

  static const _collections = [
    'captures', 'items', 'habits', 'promises', 'decisions', 'inbox', 'actions', 'countdowns', 'focus', 'tx', 'entries',
    'rooms', 'rentPays', 'roomBills', 'houseCosts', 'clocks', 'places', 'memories', 'loanPeople', 'loans', 'cards',
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
    _s.putIfAbsent('accounts', () => <dynamic>[
          {'id': 3, 'name': 'Cash', 'group': 'Cash', 'initial': 0},
          {'id': 4, 'name': 'Bank', 'group': 'Bank', 'initial': 0},
          {'id': 5, 'name': 'bKash', 'group': 'Mobile wallet', 'initial': 0},
        ]);
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

  /// How sure Jarvis must be (0.5 to 0.95) to act or decide on its own; below it, you are asked.
  double get sureEnough => ((settings['sure'] as num?) ?? 0.7).toDouble();

  /// Goes up by one on every save, so sync can tell whether anything changed.
  int changes = 0;

  void save() {
    _prefs.setString('state', jsonEncode(_s));
    changes++;
    _prefs.setBool('local_dirty', true);
    notifyListeners();
  }

  /// True when something changed here since the last sync upload (survives restarts).
  bool get dirty => _prefs.getBool('local_dirty') ?? false;

  Future<void> clearDirty(int atChanges) async {
    if (changes == atChanges) await _prefs.setBool('local_dirty', false);
  }

  /// The whole data document (for sync).
  Rec get state => _s;

  /// Replaces all data with a merged copy from sync, then re-arms reminders.
  Future<void> replaceState(Rec s) async {
    _s = s;
    _fillDefaults();
    save();
    await resyncAll();
  }

  /// Settings kept on this device only (never synced), like the sync token.
  String? local(String key) => _prefs.getString('local_$key');

  Future<void> setLocal(String key, String? value) =>
      value == null ? _prefs.remove('local_$key') : _prefs.setString('local_$key', value);

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
    var at = col == 'items' ? r['when'] as int? : r['remindAt'] as int?;
    if (col == 'items') await _syncLead(r, nid, at);
    // "Until done": it comes back at the same time every day until the item is finished.
    final untilDone = col == 'items' && r['untilDone'] == true && at != null;
    if (untilDone) at = nextDaily(at, DateTime.now());
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
    await Native.schedule(id: nid, millis: at, kind: isAlarm ? 'alarm' : 'notice', label: label, repeatDaily: untilDone);
  }

  /// [when] itself if it is still ahead, otherwise the next time the clock shows the same hour and minute.
  static int nextDaily(int when, DateTime now) {
    final w = fromMs(when);
    if (w.isAfter(now)) return when;
    var d = DateTime(now.year, now.month, now.day, w.hour, w.minute);
    if (!d.isAfter(now)) d = DateTime(now.year, now.month, now.day + 1, w.hour, w.minute);
    return d.millisecondsSinceEpoch;
  }

  /// The reminder a while before an item ("In 15 min: Physics class"), if it has one and it is still ahead.
  Future<void> _syncLead(Rec r, int nid, int? at) async {
    final lead = (r['lead'] as num?)?.toInt() ?? 0;
    final from = at == null ? null : at - lead * 60000;
    if (lead <= 0 || from == null || r['status'] != 'open' || r['allDay'] == true || from <= DateTime.now().millisecondsSinceEpoch) {
      await Native.cancel(Lead.id(nid));
      return;
    }
    await Native.schedule(id: Lead.id(nid), millis: from, kind: 'notice', label: '${Lead.short(lead)}: ${r['title']}');
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

    await daily(1, 7, 30, "Good morning. What's the one thing that matters today? Reply, or open your day.");
    await daily(2, 21, 0, 'How did today go? Reply with anything: what you did, spent, or felt.');
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

  /// A countdown reminds on the days it was set to (default: the day itself) at its time (default 9:00),
  /// as a quiet notification or, with `ring`, as an alarm.
  Future<void> _syncCountdown(Rec c) async {
    final nid = c['nid'] as int?;
    if (nid == null) return;
    if (c['kind'] == 'countup') return _cancelCountdown(nid);
    final before = (c['before'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [0];
    final time = c['time'] as String? ?? CountdownAlert.defaultTime;
    final day = countdownNext(c);
    for (final d in CountdownAlert.days) {
      final id = CountdownAlert.id(nid, d);
      final at = CountdownAlert.at(day, time, d);
      if (!before.contains(d) || !at.isAfter(DateTime.now())) {
        await Native.cancel(id);
        continue;
      }
      await Native.schedule(
        id: id,
        millis: at.millisecondsSinceEpoch,
        kind: c['ring'] == true ? 'alarm' : 'notice',
        label: CountdownAlert.label(c['title'] as String, d),
      );
    }
  }

  /// Cancels every reminder a countdown may have planned.
  Future<void> _cancelCountdown(int nid) async {
    for (final d in CountdownAlert.days) {
      await Native.cancel(CountdownAlert.id(nid, d));
    }
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

  Future<Rec> addCountdown(String title, String date, String kind,
      {List<Rec>? undo, List<int>? before, String? time, bool ring = false}) async {
    final c = <String, dynamic>{
      'id': nextId(),
      'title': title,
      'date': date,
      'kind': kind,
      'yearly': kind == 'birthday' || kind == 'anniversary',
      'nid': nextId(),
      if (before != null) 'before': before,
      if (time != null) 'time': time,
      if (ring) 'ring': true,
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
        if (nid != null && op['col'] == 'items') await Native.cancel(Lead.id(nid));
        if (nid != null && op['col'] == 'countdowns') await _cancelCountdown(nid);
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
    if (rid != null && col == 'items') Native.cancel(Lead.id(rid));
    if (rid != null && col == 'countdowns') _cancelCountdown(rid);
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
      'lead': kind == 'event' ? Lead.defaultFor(settings) : 0,
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
      'start': dayKey(DateTime.now()),
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
  DateTime periodStart(Rec h, DateTime d) => HabitCore.periodStart(h, d);

  /// Days done in the period starting at start.
  int periodCount(Rec h, DateTime start) => HabitCore.periodCount(h, start);

  /// The habit's current streak (days, or weeks/months for weekly/monthly targets).
  int streakPeriods(Rec h) => HabitCore.currentStreak(h, DateTime.now());

  /// Habits still to do today, in routine order (morning, then the rest, then evening).
  List<Rec> habitsDueToday() {
    final now = DateTime.now();
    return orderedHabits().where((h) => HabitCore.dueToday(h, now)).toList();
  }

  /// Active habits, morning routine first, evening last, then by your own order.
  List<Rec> orderedHabits({bool archived = false}) {
    int group(Rec h) => switch (h['routine']) { 'morning' => 0, 'evening' => 2, _ => 1 };
    return list('habits').where((h) => (h['archived'] == true) == archived).toList()
      ..sort((a, b) {
        final g = group(a).compareTo(group(b));
        if (g != 0) return g;
        final r = '${a['routine'] ?? ''}'.compareTo('${b['routine'] ?? ''}');
        if (r != 0) return r;
        return ((a['order'] as int?) ?? (a['id'] as int)).compareTo((b['order'] as int?) ?? (b['id'] as int));
      });
  }

  /// Sets a day: 'yes', 'no' (missed), 'skip' (rest day), a log map ({v, items, at, note, photo}), or null to clear.
  Future<void> logHabit(Rec h, String day, Object? value) async {
    final before = streakPeriods(h);
    final old = copyRec(h);
    final logs = h['logs'] as Rec;
    if (value == null) {
      logs.remove(day);
    } else {
      logs[day] = value;
    }
    final d = DateTime.parse(day);
    final verb = value == null
        ? 'Cleared'
        : (value == 'skip' || (value is Map && value['skip'] == true))
            ? 'Rest day for'
            : (value == 'no' ? 'Missed' : (HabitCore.done(h, d) ? 'Done' : 'Logged'));
    logAction('$verb ${h['name']} on $day', [
      {'op': 'put', 'col': 'habits', 'rec': old},
    ]);
    save();
    final after = streakPeriods(h);
    if (HabitCore.done(h, d) && after > before) {
      await boost('${h['name']}: $after ${HabitCore.unit(h)} streak');
    }
  }

  /// Adds to (or, for ratings and percentages, sets) today's amount for a measured habit.
  Future<void> addHabitValue(Rec h, String day, num amount, {bool set = false}) async {
    final e = Map<String, dynamic>.from(HabitCore.entry(h, day) ?? {})
      ..remove('skip')
      ..remove('miss')
      ..remove('done');
    final v = set ? amount : ((e['v'] as num?) ?? 0) + amount;
    e['v'] = v < 0 ? 0 : v;
    await logHabit(h, day, e);
  }

  // ---------- focus (pomodoro and stopwatch) ----------

  /// The running focus session, or null. Kept in storage so it survives the app being closed.
  Rec? get focusActive => _s['focusActive'] as Rec?;

  /// mode 'pomo' counts down [minutes]; 'watch' counts up. A break is a pomo that is not recorded.
  /// [deep] marks a deep-work block (a long countdown with no breaks), counted on its own.
  Future<void> startFocus({required String mode, int minutes = 25, int? taskId, String label = 'Focus', bool isBreak = false, bool deep = false}) async {
    final start = DateTime.now().millisecondsSinceEpoch;
    final f = <String, dynamic>{
      'mode': mode,
      'start': start,
      'minutes': minutes,
      'taskId': taskId,
      'label': label,
      'break': isBreak,
      if (deep) 'deep': true,
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
        if (f['deep'] == true) 'deep': true,
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

  // ---------- money ----------

  String get currency => (settings['currency'] as String?) ?? '৳';

  Map<String, dynamic> get catRules => (settings['catRules'] ??= <String, dynamic>{}) as Map<String, dynamic>;

  /// The spelling to save for a typed or spoken category (see [Cats.tidy]).
  String tidyCategory(String type, String raw) =>
      Cats.tidy(raw, type: type, rules: catRules, known: [for (final u in Cats.used(list('tx').cast<Map<String, dynamic>>(), type)) u.name]);

  /// Merges one category into another for good: moves its entries and remembers the rule.
  Future<int> mergeCategory(String type, String from, String to) async {
    final undo = <Rec>[
      for (final t in list('tx'))
        if (t['type'] == type && Cats.key((t['cat'] as String?) ?? '') == Cats.key(from)) {'op': 'put', 'col': 'tx', 'rec': copyRec(t)},
    ];
    final n = Cats.merge(list('tx').cast<Map<String, dynamic>>(), catRules, type, from, to);
    if (n > 0) logAction('Merged $from into $to ($n)', undo);
    save();
    return n;
  }

  /// type is 'income', 'expense' or 'transfer'; a transfer moves money from account to toAccount.
  Rec addTx({
    required String type,
    required num amount,
    required String category,
    required String account,
    String? toAccount,
    String? note,
    String? desc,
    List<String> tags = const [],
    int? ts,
    int? captureId,
    List<Rec>? undo,
  }) {
    final r = <String, dynamic>{
      'id': nextId(),
      'type': type,
      'amount': amount,
      'cat': type == 'transfer' ? category : (tidyCategory(type, category).isEmpty ? 'Other' : tidyCategory(type, category)),
      'account': account,
      'toAccount': toAccount,
      'note': note,
      'desc': desc,
      'tags': tags,
      'ts': ts ?? DateTime.now().millisecondsSinceEpoch,
      'captureId': captureId,
    };
    list('tx').add(r);
    undo?.add({'op': 'rm', 'col': 'tx', 'id': r['id']});
    save();
    return r;
  }

  /// Opening amount plus everything that went in and out of the account.
  num balance(Rec account) {
    final name = account['name'];
    num b = (account['initial'] as num?) ?? 0;
    for (final t in list('tx')) {
      final a = t['amount'] as num;
      if (t['type'] == 'income' && t['account'] == name) b += a;
      if (t['type'] == 'expense' && t['account'] == name) b -= a;
      if (t['type'] == 'transfer') {
        if (t['account'] == name) b -= a;
        if (t['toAccount'] == name) b += a;
      }
    }
    return b;
  }

  /// Formats an amount like 1,234.50 with the currency sign.
  String money(num v) {
    final neg = v < 0;
    final parts = v.abs().toStringAsFixed(2).split('.');
    final whole = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    final frac = parts[1] == '00' ? '' : '.${parts[1]}';
    return '${neg ? '-' : ''}$currency$whole$frac';
  }

  // ---------- journal ----------

  List<Rec> capturesOn(String day) => list('captures')
      .where((c) => c['status'] == 'done' && dayKey(fromMs(c['ts'] as int)) == day)
      .toList();

  /// Written journal entries of a day, oldest first.
  List<Rec> entriesOn(String day) =>
      list('entries').where((e) => dayKey(fromMs(e['ts'] as int)) == day).toList()
        ..sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));

  /// The day's mood (1 awful to 5 great): the last journal entry that has one, or else what Jarvis heard in notes.
  int? dayMood(String day) {
    int? m;
    for (final e in entriesOn(day)) {
      if (e['mood'] != null) m = e['mood'] as int;
    }
    if (m != null) return m;
    for (final c in capturesOn(day)) {
      if (c['mood'] != null) m = c['mood'] as int;
    }
    return m;
  }

  /// Days with a written entry or a processed note, newest first.
  List<String> journalDays() {
    final days = <String>{};
    for (final c in list('captures')) {
      if (c['status'] == 'done') days.add(dayKey(fromMs(c['ts'] as int)));
    }
    for (final e in list('entries')) {
      days.add(dayKey(fromMs(e['ts'] as int)));
    }
    return days.toList()..sort((a, b) => b.compareTo(a));
  }

  /// Days in a row, up to today (or yesterday, so the streak survives until tonight), with something written.
  int journalStreak() {
    final days = journalDays().toSet();
    final now = DateTime.now();
    var d = DateTime(now.year, now.month, now.day);
    if (!days.contains(dayKey(d))) d = DateTime(d.year, d.month, d.day - 1);
    var n = 0;
    while (days.contains(dayKey(d))) {
      n++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return n;
  }

  /// What the rest of Jarvis knows about a day, for the "Your day" card and the AI.
  List<String> dayFacts(String day) {
    bool on(int? ms) => ms != null && dayKey(fromMs(ms)) == day;
    final done = list('items').where((i) => i['status'] == 'done' && on(i['doneAt'] as int?)).map((i) => i['title']).toList();
    final events = list('items')
        .where((i) => i['kind'] == 'event' && i['status'] != 'cancelled' && on(i['when'] as int?))
        .map((i) => i['title'])
        .toList();
    final habits = list('habits').where((h) => HabitCore.done(h, DateTime.parse(day))).map((h) => h['name']).toList();
    final skipped = list('habits')
        .where((h) => HabitCore.entry(h, day)?['miss'] == true || HabitCore.skipped(h, DateTime.parse(day)))
        .map((h) => h['name'])
        .toList();
    final focus = list('focus').where((f) => on(f['start'] as int)).fold<int>(0, (a, f) => a + (f['minutes'] as int));
    num spent = 0;
    num earned = 0;
    for (final t in list('tx').where((t) => on(t['ts'] as int))) {
      if (t['type'] == 'expense') spent += t['amount'] as num;
      if (t['type'] == 'income') earned += t['amount'] as num;
    }
    return [
      if (done.isNotEmpty) 'Finished: ${done.join(', ')}',
      if (events.isNotEmpty) 'Events: ${events.join(', ')}',
      if (habits.isNotEmpty) 'Habits done: ${habits.join(', ')}',
      if (skipped.isNotEmpty) 'Habits skipped: ${skipped.join(', ')}',
      if (focus > 0) 'Focused ${focus ~/ 60}h ${focus % 60}m',
      if (spent > 0) 'Spent ${money(spent)}',
      if (earned > 0) 'Received ${money(earned)}',
    ];
  }

  /// Notes and entries from today's month and day in earlier years, as (year, text).
  List<(int, String)> onThisDay() {
    final now = DateTime.now();
    bool match(int ms) {
      final d = fromMs(ms);
      return d.year < now.year && d.month == now.month && d.day == now.day;
    }

    return [
      for (final c in list('captures'))
        if (c['status'] == 'done' && match(c['ts'] as int)) (fromMs(c['ts'] as int).year, c['cleaned'] as String),
      for (final e in list('entries'))
        if (match(e['ts'] as int)) (fromMs(e['ts'] as int).year, e['text'] as String),
    ];
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
