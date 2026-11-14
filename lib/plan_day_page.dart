import 'package:flutter/material.dart';

import 'day_planner.dart';
import 'focus_screen.dart';
import 'habit_core.dart';
import 'haptics.dart';
import 'items_screen.dart' show MatrixPage;
import 'needs.dart';
import 'needs_editor.dart';
import 'piece_facts.dart';
import 'store.dart';
import 'task_sheet.dart';

/// The one place to plan a day (today unless one is chosen). The pieces of a day are tasks and habits.
/// Drag a piece from the tray into the day, or onto another piece to link them ("only if that one is done",
/// "only if it is not"); drag a condition (money, a countdown) onto a piece. Jarvis works out the times.
/// Tap a piece for its time, length, blocks, importance for the day, links, or another day.
/// Apply gives each piece its time, so the day is on the calendar and can be edited there.
class PlanDayPage extends StatefulWidget {
  const PlanDayPage({super.key, required this.store, this.day});
  final Store store;

  /// The day to plan. Today when null.
  final DateTime? day;

  @override
  State<PlanDayPage> createState() => _PlanDayPageState();
}

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _dayName(DateTime d) {
  final now = DateTime.now();
  final diff = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  final base = '${_weekdayNames[d.weekday - 1]} ${d.day} ${_monthNames[d.month - 1]}';
  return diff == 0 ? 'Today, $base' : (diff == 1 ? 'Tomorrow, $base' : base);
}

String _hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

void startDeepWork(BuildContext context, Store s, {int? taskId}) => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(appBar: AppBar(title: const Text('Focus')), body: FocusScreen(store: s, taskId: taskId, deep: true)),
      ),
    );

/// What is being dragged: a piece (a task's id, or minus a habit's id), or a kind of condition.
class _Drag {
  const _Drag.piece(int this.piece, this.title) : condition = null;
  const _Drag.condition(String this.condition, this.title) : piece = null;
  final int? piece;
  final String? condition;
  final String title;
}

class _PlanDayPageState extends State<PlanDayPage> {
  Store get store => widget.store;

  late DateTime _day = DateTime(widget.day?.year ?? DateTime.now().year, widget.day?.month ?? DateTime.now().month, widget.day?.day ?? DateTime.now().day);

  /// Changes made on this page; they are written to the tasks only on Apply.
  final _edits = <int, PlanEdit>{};

  /// Pieces added to this day by hand: task ids, and habits as minus their id.
  final _extra = <int>{};

  /// Tasks planned earlier keep their time, unless Jarvis is asked to place them again.
  final _unpinned = <int>{};
  bool _replan = false;

  /// The tray's tab: 0 tasks, 1 habits, 2 conditions.
  int _tab = 0;

  bool get _isToday => dayKey(_day) == dayKey(DateTime.now());

  /// The piece an item id on the plan stands for (a habit's planned task is that habit).
  int _piece(int id) {
    if (id < 0) return id;
    final it = store.byId('items', id);
    return it == null ? id : DayPlanner.pieceId(it);
  }

  /// The record that holds a piece's links: the task, or the habit.
  Rec? _owner(int piece) => piece < 0 ? store.byId('habits', -piece) : store.byId('items', piece);

  String _titleOf(int piece) => '${(_owner(piece) ?? const {})[piece < 0 ? 'name' : 'title']}';

  /// The plan for [day] (this page's day when null), with [extra] added to it.
  DayPlan _plan({DateTime? day, Set<int>? extra}) {
    final now = DateTime.now();
    final d = day ?? _day;
    final key = dayKey(d);
    final added = extra ?? _extra;
    final all = store.list('items').cast<Map<String, dynamic>>();
    // A habit's planned task from an earlier day is stale: the day gets a fresh one.
    final open = all.where((i) => i['status'] == 'open' && (i['planHabit'] == null || i['habitDay'] == key)).toList();
    final parts = all.where((i) => i['partOf'] != null && i['status'] == 'done').toList();
    final habits = DayPlanner.habitTasks(store.list('habits').cast<Map<String, dynamic>>(), d, items: all, extra: added);
    // A habit with a reminder time (later today, or on another day) starts at that time, unless you moved it.
    final pins = <int, PlanEdit>{
      for (final t in habits)
        if (t['quick'] != true)
          if (_remindAt(store.byId('habits', t['habitId'] as int), d, now) case final at?) t['id'] as int: PlanEdit(start: at),
    };
    // A task planned for this day keeps its time (also when it was moved on the calendar).
    final kept = <int, PlanEdit>{
      if (!_replan)
        for (final i in open)
          if (i['kind'] == 'task' && i['planned'] == key && i['allDay'] != true && i['when'] is int && !_unpinned.contains(i['id']))
            i['id'] as int: PlanEdit(start: DateTime.fromMillisecondsSinceEpoch(i['when'] as int)),
    };
    final ratios = <String, double>{
      for (final i in open)
        if (i['cat'] != null && store.estimateSuggestion(i['cat'] as String, 60) != null)
          i['cat'] as String: store.estimateSuggestion(i['cat'] as String, 60)!.ratio,
    };
    final edits = {...kept, ...pins, ..._edits};
    DayPlan run(Map<int, NeedResult> needs) => DayPlanner.plan(
          now: now,
          day: d,
          extra: added,
          items: [...open, ...parts, ...habits, ...store.phoneEvents],
          ratios: ratios,
          edits: edits,
          needs: needs,
        );
    // Links: first see which pieces the day holds, then where each linked piece stands among them.
    final linked = [...open, ...habits].where((i) => i['kind'] == 'task').toList();
    Object? needsOf(Map<String, dynamic> i) {
      final id = i['id'] as int;
      if (id < 0) return (store.byId('habits', -id) ?? const {})['needs'];
      return PieceFacts(store).needsOf(i);
    }

    if (!linked.any((i) => Needs.has(needsOf(i)))) return run(const {});
    final first = run(const {});
    final present = {
      for (final b in [...first.blocks.where((b) => !b.fixed), ...first.overflow, ...first.quick, ...first.skipped])
        if (b.itemId != null) _piece(b.itemId!),
    };
    final facts = PieceFacts(
      store,
      day: d,
      present: present,
      skipped: {for (final e in _edits.entries) if (e.value.skip) _piece(e.key)},
    );
    final needs = <int, NeedResult>{};
    for (final i in linked) {
      final n = needsOf(i);
      if (Needs.has(n)) needs[i['id'] as int] = facts.stateOf(n);
    }
    return run(needs);
  }

  DateTime? _remindAt(Rec? h, DateTime day, DateTime now) {
    final r = h?['remind'] as String?;
    if (r == null) return null;
    final p = r.split(':');
    final at = DateTime(day.year, day.month, day.day, int.parse(p[0]), int.parse(p[1]));
    return at.isAfter(now) ? at : null;
  }

  void _goTo(DateTime d) => setState(() {
        _day = DateTime(d.year, d.month, d.day);
        _edits.clear();
        _extra.clear();
        _unpinned.clear();
        _replan = false;
      });

  /// Writes the window and longest length chosen here onto the task, so they stay with it.
  void _keepLimits(Rec it, PlanEdit? e) {
    if (e == null) return;
    if (e.noWindow) {
      it.remove('winFrom');
      it.remove('winTo');
    } else {
      if (e.from != null) it['winFrom'] = e.from;
      if (e.to != null) it['winTo'] = e.to;
    }
    if (e.max != null) it['estMax'] = e.max;
  }

  Future<void> _apply(BuildContext context, DayPlan plan) async {
    Haptics.success();
    final undo = <Rec>[];
    for (final b in plan.blocks.where((b) => !b.fixed && (b.itemId ?? 0) < 0)) {
      // A habit's time: a task linked to the habit, so ticking it off logs the habit.
      await store.addItem(
        kind: 'task',
        title: b.title,
        when: b.start.millisecondsSinceEpoch,
        est: b.minutes,
        undo: undo,
        extra: {'planHabit': -b.itemId!, 'habitDay': dayKey(_day), 'list': 'Habits', 'allDay': false, 'quick': false, 'planned': dayKey(_day)},
      );
    }
    for (final b in plan.blocks.where((b) => !b.fixed && (b.itemId ?? 0) > 0)) {
      final it = store.byId('items', b.itemId);
      if (it == null) continue;
      if (b.part != null) {
        // One block of a task done in blocks: a part of its own, which counts toward the task when done.
        await store.addItem(
          kind: 'task',
          title: '${b.title} (block)',
          when: b.start.millisecondsSinceEpoch,
          est: b.minutes,
          undo: undo,
          extra: {
            'partOf': it['id'], 'planned': dayKey(_day), 'allDay': false, 'quick': false,
            'list': it['list'], 'priority': it['priority'] ?? 0, 'color': it['color'], 'needs': it['needs'],
          },
        );
        continue;
      }
      undo.add({'op': 'put', 'col': 'items', 'rec': copyRec(it)});
      it['when'] = b.start.millisecondsSinceEpoch;
      it['allDay'] = false;
      it['planned'] = dayKey(_day);
      _keepLimits(it, _edits[b.itemId]);
      if (_edits[b.itemId]?.minutes != null) {
        it['est'] = b.minutes;
      } else {
        it['est'] ??= b.minutes;
      }
      it['nid'] ??= store.nextId();
      await store.syncRecord('items', it);
    }
    store.logAction('Planned ${_dayName(_day)} (${undo.length} tasks)', undo);
    store.save();
    if (!mounted) return;
    setState(() {
      _edits.clear();
      _unpinned.clear();
      _replan = false;
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Planned. It is on your calendar, with a reminder as each one starts.')));
    }
  }

  /// Moves tasks to another day (all-day there, so that day's plan picks them up). Undo restores them.
  Future<void> _moveTo(BuildContext context, List<int?> ids, DateTime target) async {
    final undo = <Rec>[];
    for (final id in ids) {
      final it = store.byId('items', id);
      if (it == null) continue;
      undo.add({'op': 'put', 'col': 'items', 'rec': copyRec(it)});
      it['when'] = DateTime(target.year, target.month, target.day, 9).millisecondsSinceEpoch;
      it['allDay'] = true;
      it.remove('planned');
      it['postponed'] = ((it['postponed'] as int?) ?? 0) + 1;
      _keepLimits(it, _edits[id]);
      _edits.remove(id);
      _extra.remove(id);
      it.remove('dayPri');
      await store.syncRecord('items', it);
    }
    store.logAction('Moved ${undo.length} task${undo.length == 1 ? '' : 's'} to ${_dayName(target)}', undo);
    store.save();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Moved to ${_dayName(target)}.')));
    }
  }

  Future<void> _pickDayFor(BuildContext context, List<int?> ids) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(_day.year, _day.month, _day.day + 1),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (d != null && context.mounted) await _moveTo(context, ids, d);
  }

  /// The nearest day within three weeks where all of [left] fit alongside what is already planned.
  DateTime? _nextRoom(DayPlan plan) {
    final ids = {for (final b in plan.overflow) if (b.itemId != null) b.itemId!};
    if (ids.isEmpty) return null;
    for (var k = 1; k <= 21; k++) {
      final d = DateTime(_day.year, _day.month, _day.day + k);
      final p = _plan(day: d, extra: {..._extra, ...ids});
      if (!p.overflow.any((b) => ids.contains(b.itemId))) return d;
    }
    return null;
  }

  bool _hasWindow(int? id) {
    if (_edits[id]?.noWindow == true) return false;
    final it = store.byId('items', id);
    return _edits[id]?.from != null || _edits[id]?.to != null || it?['winFrom'] != null || it?['winTo'] != null;
  }

  void _change(int id, PlanEdit Function(PlanEdit) f) => setState(() => _edits[id] = f(_edits[id] ?? const PlanEdit()));

  // ---------- pieces: adding, linking, finishing ----------

  void _addToDay(int piece) {
    Haptics.tap();
    setState(() {
      _extra.add(piece);
      _edits.removeWhere((id, e) => e.skip && _piece(id) == piece);
    });
  }

  Future<void> _setNeeds(int piece, Object? needs, {String key = 'needs'}) async {
    final rec = _owner(piece);
    if (rec == null) return;
    await store.updateRec(piece < 0 ? 'habits' : 'items', rec, '${needs == null ? 'Unlinked' : 'Linked'}: ${_titleOf(piece)}',
        (r) => needs == null ? r.remove(key) : r[key] = needs);
  }

  Future<void> _addCheck(int piece, Map<String, dynamic> check) async {
    final old = _owner(piece)?['needs'];
    await _setNeeds(piece, {'any': old is Map && old['any'] == true, 'if': [...Needs.checks(old), check]});
  }

  /// Something from the tray, or another piece, was dropped on [target].
  Future<void> _dropOn(int target, _Drag d) async {
    Haptics.dragEnd();
    if (d.condition != null) {
      final check = d.condition == 'money' ? await pickBalance(context, store) : await pickCountdown(context, store);
      if (check != null) await _addCheck(target, check);
      return;
    }
    final piece = d.piece!;
    final not = await pickDone(context, _titleOf(target));
    if (not == null) return;
    await _addCheck(piece, {'check': 'done', 'id': target, if (not) 'not': true});
    if (mounted) _addToDay(piece);
  }

  Future<void> _done(int itemId) async {
    Haptics.success();
    if (itemId > 0) {
      final it = store.byId('items', itemId);
      if (it != null) await store.markDone(it);
      return;
    }
    final h = store.byId('habits', -itemId);
    if (h != null) await store.logHabit(h, dayKey(_day), (h['type'] ?? 'yesno') == 'yesno' ? 'yes' : {'v': h['target'] ?? 1});
  }

  /// Whether Apply would change anything: a proposed time that is not on the calendar yet.
  bool _dirty(DayPlan plan) => plan.blocks.any((b) {
        if (b.fixed || b.itemId == null) return false;
        if (b.itemId! < 0 || b.part != null) return true;
        final it = store.byId('items', b.itemId);
        return it == null || it['planned'] != dayKey(_day) || it['when'] != b.start.millisecondsSinceEpoch || it['allDay'] == true || (it['est'] ?? b.minutes) != b.minutes;
      });

  Future<void> _adjust(BuildContext context, PlanBlock b) async {
    final id = b.itemId;
    final it = id == null ? null : store.byId('items', id);
    if (id == null || (it == null && id > 0)) return;
    if (b.fixed && it != null) return showTaskSheet(context, store, item: it);
    final piece = _piece(id);
    var start = b.start;
    var minutes = b.minutes;
    final own = _edits[id];
    int? from = own?.noWindow == true ? null : (own?.from ?? (it?['winFrom'] as num?)?.toInt());
    int? to = own?.noWindow == true ? null : (own?.to ?? (it?['winTo'] as num?)?.toInt());
    int? most = own?.max ?? (it?['estMax'] as num?)?.toInt();
    final chunk = (it?['chunk'] as num?)?.toInt() ?? 0;
    final split = chunk > 0 && ((it?['est'] as int?) ?? 0) > chunk;
    final timed = b.minutes > 0;
    Future<int?> pickTime(BuildContext ctx, int? at) async {
      final t = await showTimePicker(context: ctx, initialTime: TimeOfDay(hour: (at ?? 540) ~/ 60, minute: (at ?? 540) % 60));
      return t == null ? null : t.hour * 60 + t.minute;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ListenableBuilder(
        listenable: store,
        builder: (ctx, _) => StatefulBuilder(
          builder: (ctx, setS) {
            final tt = Theme.of(ctx).textTheme;
            final scheme = Theme.of(ctx).colorScheme;
            final rec = _owner(piece);
            final dayPri = it?['dayPri'] is Map && (it!['dayPri'] as Map)['day'] == dayKey(_day) ? (it['dayPri'] as Map)['p'] as int? : null;
            Widget label(String text) => Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 8),
                  child: Text(text, style: tt.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
                );
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.86),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.title, style: tt.titleLarge),
                    if (timed && !split) ...[
                      label('Time'),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.schedule),
                            label: Text('Starts ${clock(start.millisecondsSinceEpoch)}'),
                            onPressed: () async {
                              final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(start));
                              if (t == null) return;
                              setS(() => start = DateTime(start.year, start.month, start.day, t.hour, t.minute));
                              _change(id, (e) => e.copyWith(start: start));
                            },
                          ),
                        ),
                        if (_edits[id]?.start != null || (it?['planned'] == dayKey(_day) && !_unpinned.contains(id) && !_replan)) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              _unpinned.add(id);
                              _change(id, (e) => e.copyWith(clearStart: true));
                              Navigator.pop(ctx);
                            },
                            child: const Text('Let Jarvis place it'),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        IconButton.filledTonal(
                          tooltip: 'Shorter',
                          icon: const Icon(Icons.remove),
                          onPressed: minutes <= 5
                              ? null
                              : () {
                                  setS(() => minutes -= minutes > 60 ? 15 : 5);
                                  _change(id, (e) => e.copyWith(minutes: minutes));
                                },
                        ),
                        Expanded(
                          child: Column(children: [
                            Text(fmtMinutes(minutes), style: tt.titleMedium),
                            if (most != null && most! > minutes) Text('up to ${fmtMinutes(most!)}', style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                          ]),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Longer',
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            setS(() => minutes += minutes >= 60 ? 15 : 5);
                            _change(id, (e) => e.copyWith(minutes: minutes));
                          },
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        ActionChip(
                          avatar: const Icon(Icons.unfold_more, size: 18),
                          label: Text(most == null || most! <= minutes ? 'Can take longer' : 'Up to ${fmtMinutes(most!)}'),
                          onPressed: () {
                            setS(() => most = (most == null || most! < minutes ? minutes : most!) + (minutes >= 60 ? 30 : 15));
                            _change(id, (e) => e.copyWith(max: most));
                          },
                        ),
                        if (most != null && most! > minutes)
                          ActionChip(
                            label: const Text('Fixed length'),
                            onPressed: () {
                              setS(() => most = minutes);
                              _change(id, (e) => e.copyWith(max: minutes));
                            },
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.wb_twilight, size: 18),
                          label: Text(from == null ? 'Not before' : 'Not before ${_hm(from!)}'),
                          onPressed: () async {
                            final m = await pickTime(ctx, from);
                            if (m == null) return;
                            setS(() => from = m);
                            _change(id, (e) => e.copyWith(from: m, noWindow: false));
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.flag_outlined, size: 18),
                          label: Text(to == null ? 'Done by' : 'Done by ${_hm(to!)}'),
                          onPressed: () async {
                            final m = await pickTime(ctx, to);
                            if (m == null) return;
                            setS(() => to = m);
                            _change(id, (e) => e.copyWith(to: m, noWindow: false));
                          },
                        ),
                        if (from != null || to != null)
                          ActionChip(
                            label: const Text('Any time of day'),
                            onPressed: () {
                              setS(() {
                                from = null;
                                to = null;
                              });
                              _change(id, (e) => e.copyWith(noWindow: true));
                            },
                          ),
                      ]),
                    ],
                    if (split) ...[
                      label('Blocks of ${fmtMinutes(chunk)} on this day'),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        ChoiceChip(
                          label: const Text('As many as fit'),
                          selected: _edits[id]?.blocks == null,
                          onSelected: (_) {
                            setState(() => _edits.remove(id));
                            setS(() {});
                          },
                        ),
                        for (var n = 1; n <= 4; n++)
                          ChoiceChip(
                            label: Text('$n'),
                            selected: _edits[id]?.blocks == n,
                            onSelected: (_) {
                              _change(id, (e) => e.copyWith(blocks: n));
                              setS(() {});
                            },
                          ),
                      ]),
                    ],
                    if (it != null) ...[
                      label(_isToday ? 'Importance today' : 'Importance on this day'),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        ChoiceChip(
                          label: Text('As usual (${priorityNames[(it['priority'] as int?) ?? 0]})'),
                          selected: dayPri == null,
                          onSelected: (_) => store.updateRec('items', it, '${it['title']}: usual importance', (r) => r.remove('dayPri')),
                        ),
                        for (final p in [3, 2, 1])
                          ChoiceChip(
                            avatar: Icon(Icons.flag, size: 18, color: priorityColors[p]),
                            showCheckmark: false,
                            label: Text(priorityNames[p]),
                            selected: dayPri == p,
                            onSelected: (_) => store.updateRec('items', it, '${it['title']}: ${priorityNames[p]} for ${_dayName(_day)}',
                                (r) => r['dayPri'] = {'day': dayKey(_day), 'p': p}),
                          ),
                      ]),
                    ],
                    label('Only if'),
                    NeedsEditor(store: store, needs: rec?['needs'], self: piece, onChanged: (v) => _setNeeds(piece, v)),
                    if (Needs.has(rec?['needs']))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.alt_route),
                          label: const Text('Otherwise, do another task instead'),
                          onPressed: () async {
                            final other = await pickPiece(ctx, store, habits: false, self: piece);
                            if (other == null) return;
                            await _setNeeds(other.id, Needs.opposite(rec?['needs']));
                            if (mounted) _addToDay(other.id);
                          },
                        ),
                      ),
                    label('Counts as done when'),
                    NeedsEditor(store: store, needs: rec?['doneIf'], self: piece, onChanged: (v) => _setNeeds(piece, v, key: 'doneIf')),
                    label('Not ${_isToday ? 'today' : 'this day'}'),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      ActionChip(
                        avatar: const Icon(Icons.event_busy, size: 18),
                        label: const Text('Leave out'),
                        onPressed: () {
                          _extra.remove(piece);
                          _change(id, (e) => e.copyWith(skip: true));
                          Navigator.pop(ctx);
                        },
                      ),
                      if (it != null && it['planHabit'] == null) ...[
                        for (final (text, days) in [('Tomorrow', 1), ('In 3 days', 3), ('In a week', 7)])
                          ActionChip(
                            label: Text(text),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _moveTo(context, [id], DateTime(_day.year, _day.month, _day.day + days));
                            },
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.calendar_month, size: 18),
                          label: const Text('Pick a day'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _pickDayFor(context, [id]);
                          },
                        ),
                      ],
                    ]),
                    if (it != null && it['planHabit'] == null) ...[
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, children: [
                        TextButton.icon(
                          icon: const Icon(Icons.tune),
                          label: const Text('All options'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            showTaskSheet(context, store, item: it);
                          },
                        ),
                        TextButton.icon(
                          icon: Icon(timed ? Icons.bolt : Icons.hourglass_empty),
                          label: Text(timed ? 'Quick, no time needed' : 'It takes time'),
                          onPressed: () {
                            store.updateRec('items', it, '${it['title']}: ${timed ? 'quick' : 'takes time'}', (r) => r['quick'] = timed);
                            Navigator.pop(ctx);
                          },
                        ),
                      ]),
                    ],
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ---------- the page ----------

  Widget _sectionTitle(String text, {Color? color}) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color ?? Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  /// A small draggable chip in the tray.
  Widget _trayChip(_Drag data, IconData icon, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: LongPressDraggable<_Drag>(
        data: data,
        onDragStarted: Haptics.dragStart,
        feedback: _feedback(data.title),
        child: ActionChip(avatar: Icon(icon, size: 18, color: scheme.primary), label: Text(data.title), onPressed: onTap),
      ),
    );
  }

  Widget _feedback(String title) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSurface)),
        ),
      ),
    );
  }

  /// One piece of the day. Hold and drag it onto another piece to link them; drop things on it to link to it.
  Widget _pieceCard(PlanBlock b, {String? status}) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final id = b.itemId;
    final it = id != null && id > 0 ? store.byId('items', id) : null;
    final habit = (id ?? 0) < 0 || it?['planHabit'] != null;
    final piece = id == null ? null : _piece(id);
    final timed = b.minutes > 0 && status == null;
    final needs = piece == null ? null : _owner(piece)?['needs'];
    final link = b.fixed || !Needs.has(needs) ? null : (b.reason ?? 'Only if ${Needs.describe(needs, name: PieceFacts(store).name, money: store.money)}');
    final line = [
      if (timed) '${clock(b.start.millisecondsSinceEpoch)} – ${clock(b.end.millisecondsSinceEpoch)}',
      if (timed) fmtMinutes(b.minutes),
      if (b.part != null) 'block ${b.part} of ${b.parts}',
      if (b.fixed) 'on your calendar',
      if (!b.fixed && _hasWindow(id)) 'has a time window',
      if (status != null) status,
    ].join('  ·  ');
    Widget card(bool hot) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: b.fixed ? scheme.surfaceContainerHighest : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: hot ? BorderSide(color: scheme.primary, width: 2) : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _adjust(context, b),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
              child: Row(children: [
                if (b.fixed || id == null)
                  const SizedBox(width: 48, height: 48, child: Icon(Icons.event))
                else
                  IconButton(
                    tooltip: 'Done',
                    icon: Icon(habit ? Icons.local_fire_department_outlined : Icons.radio_button_unchecked, color: scheme.primary),
                    onPressed: () => _done(id),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b.title, style: tt.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (line.isNotEmpty) Text(line, style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      if (link != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(children: [
                            Icon(Icons.link, size: 14, color: scheme.primary),
                            const SizedBox(width: 4),
                            Expanded(child: Text(link, style: tt.bodySmall?.copyWith(color: scheme.primary), maxLines: 2, overflow: TextOverflow.ellipsis)),
                          ]),
                        ),
                    ]),
                  ),
                ),
                if (!b.fixed) Icon(Icons.drag_indicator, color: scheme.outline),
              ]),
            ),
          ),
        );
    if (b.fixed || piece == null) return card(false);
    return DragTarget<_Drag>(
      onWillAcceptWithDetails: (d) => d.data.piece != piece,
      onAcceptWithDetails: (d) => _dropOn(piece, d.data),
      builder: (context, candidates, _) => LongPressDraggable<_Drag>(
        data: _Drag.piece(piece, b.title),
        onDragStarted: Haptics.dragStart,
        feedback: _feedback(b.title),
        child: card(candidates.isNotEmpty),
      ),
    );
  }

  /// The block to do now, or the next one, today.
  PlanBlock? _nowBlock(DayPlan plan) {
    if (!_isToday) return null;
    final now = DateTime.now();
    final mine = plan.blocks.where((b) => !b.fixed && b.itemId != null && b.end.isAfter(now)).toList();
    return mine.isEmpty ? null : mine.first;
  }

  Widget _tray(DayPlan plan, Set<int> present) {
    final scheme = Theme.of(context).colorScheme;
    final tasks = store
        .list('items')
        .where((i) => i['kind'] == 'task' && i['status'] == 'open' && i['planHabit'] == null && i['partOf'] == null && !present.contains(i['id']))
        .toList()
      ..sort((a, b) => ((a['when'] as int?) ?? 1 << 60).compareTo((b['when'] as int?) ?? 1 << 60));
    final habits = store.orderedHabits().where((h) => !present.contains(-(h['id'] as int)) && !HabitCore.done(h, _day)).toList();
    final chips = switch (_tab) {
      0 => [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('New task'), onPressed: () => showTaskSheet(context, store, day: _day)),
          ),
          for (final i in tasks) _trayChip(_Drag.piece(i['id'] as int, '${i['title']}'), Icons.radio_button_unchecked, () => _addToDay(i['id'] as int)),
        ],
      1 => [
          for (final h in habits) _trayChip(_Drag.piece(-(h['id'] as int), '${h['name']}'), Icons.local_fire_department_outlined, () => _addToDay(-(h['id'] as int))),
        ],
      _ => [
          for (final (kind, title, icon) in [('money', 'Money', Icons.account_balance_wallet_outlined), ('countdown', 'Countdown', Icons.hourglass_top)])
            _trayChip(_Drag.condition(kind, title), icon, () {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('Hold it, then drag it onto a piece of the day.')));
            }),
        ],
    };
    final empty = switch (_tab) { 0 => null, 1 => habits.isEmpty ? 'Every habit is in the day, or done.' : null, _ => null };
    return Material(
      color: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 0, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, children: [
              for (final (k, text) in [(0, 'Tasks ${tasks.length}'), (1, 'Habits ${habits.length}'), (2, 'Conditions')])
                ChoiceChip(label: Text(text), showCheckmark: false, selected: _tab == k, onSelected: (_) => setState(() => _tab = k)),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: empty != null
                  ? Align(alignment: Alignment.centerLeft, child: Text(empty, style: TextStyle(color: scheme.onSurfaceVariant)))
                  : ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(right: 8), children: chips),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                _tab == 2 ? 'Hold a condition and drag it onto a piece.' : 'Tap to add to the day. Hold and drag onto a piece to link them.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final plan = _plan();
          final scheme = Theme.of(context).colorScheme;
          final tt = Theme.of(context).textTheme;
          final mine = plan.blocks.where((b) => !b.fixed).length;
          final busy = plan.blocks.fold<int>(0, (a, b) => a + b.minutes);
          final room = _nextRoom(plan);
          final planned = plan.blocks.any((b) => !b.fixed && store.byId('items', b.itemId)?['planned'] == dayKey(_day));
          final present = {
            for (final b in [...plan.blocks.where((b) => !b.fixed), ...plan.overflow, ...plan.quick, ...plan.standby, ...plan.off])
              if (b.itemId != null) _piece(b.itemId!),
          };
          final now = _nowBlock(plan);
          final changed = _edits.isNotEmpty || _unpinned.isNotEmpty || _replan || _extra.isNotEmpty;
          final nothing = mine == 0 && plan.overflow.isEmpty && plan.quick.isEmpty && plan.standby.isEmpty && plan.off.isEmpty;
          return Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              title: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'Previous day', icon: const Icon(Icons.chevron_left), onPressed: () => _goTo(DateTime(_day.year, _day.month, _day.day - 1))),
                Flexible(
                  child: TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _day,
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                      );
                      if (d != null) _goTo(d);
                    },
                    child: Text(_dayName(_day), style: tt.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                IconButton(tooltip: 'Next day', icon: const Icon(Icons.chevron_right), onPressed: () => _goTo(DateTime(_day.year, _day.month, _day.day + 1))),
              ]),
              actions: [
                if (changed)
                  IconButton(
                    tooltip: 'Reset changes',
                    icon: const Icon(Icons.restart_alt),
                    onPressed: () => setState(() {
                      _edits.clear();
                      _unpinned.clear();
                      _extra.clear();
                      _replan = false;
                    }),
                  ),
                IconButton(
                  tooltip: 'Importance matrix',
                  icon: const Icon(Icons.grid_view),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MatrixPage(store: store))),
                ),
              ],
            ),
            floatingActionButton: _dirty(plan)
                ? FloatingActionButton.extended(icon: const Icon(Icons.check), label: const Text('Apply plan'), onPressed: () => _apply(context, plan))
                : null,
            bottomNavigationBar: _tray(plan, present),
            body: DragTarget<_Drag>(
              onWillAcceptWithDetails: (d) => d.data.piece != null && !present.contains(d.data.piece),
              onAcceptWithDetails: (d) => _addToDay(d.data.piece!),
              builder: (context, candidates, _) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                children: [
                  Text('Plan my day', style: tt.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    nothing
                        ? 'Nothing here yet. Add the tasks and habits you want for ${_isToday ? 'today' : 'this day'} from the tray below.'
                        : '$mine piece${mine == 1 ? '' : 's'} placed, ${fmtMinutes(busy)} in all, with 10 minute breaks.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  for (final n in plan.notes)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.insights, size: 16, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(n)),
                      ]),
                    ),
                  if (planned)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.auto_fix_high),
                        label: const Text('Place everything again'),
                        onPressed: () => setState(() => _replan = true),
                      ),
                    ),
                  if (candidates.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: scheme.primary, width: 2),
                      ),
                      child: Text('Drop it here to add it to ${_isToday ? 'today' : 'this day'}', style: tt.titleSmall),
                    ),
                  if (now != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      margin: EdgeInsets.zero,
                      color: scheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(now.start.isAfter(DateTime.now()) ? 'Next, at ${clock(now.start.millisecondsSinceEpoch)}' : 'Now, until ${clock(now.end.millisecondsSinceEpoch)}',
                              style: tt.labelLarge),
                          const SizedBox(height: 4),
                          Text(now.title, style: tt.titleLarge),
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, children: [
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.center_focus_strong),
                              label: const Text('Start focus'),
                              onPressed: () => startDeepWork(context, store, taskId: now.itemId! > 0 ? now.itemId : null),
                            ),
                            TextButton(onPressed: () => _done(now.itemId!), child: const Text('Done')),
                          ]),
                        ]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  for (final b in plan.blocks) _pieceCard(b),
                  if (plan.overflow.isNotEmpty) ...[
                    _sectionTitle(_isToday ? "Doesn't fit today" : "Doesn't fit this day", color: scheme.error),
                    for (final b in plan.overflow) _pieceCard(PlanBlock(b.title, _day, b.minutes, itemId: b.itemId), status: b.reason ?? fmtMinutes(b.minutes)),
                    Wrap(spacing: 8, children: [
                      if (room != null)
                        TextButton.icon(
                          icon: const Icon(Icons.redo),
                          label: Text('Move to ${_dayName(room)} (they fit)'),
                          onPressed: () => _moveTo(context, [for (final b in plan.overflow) b.itemId], room),
                        ),
                      TextButton.icon(
                        icon: const Icon(Icons.calendar_month),
                        label: const Text('Pick a day'),
                        onPressed: () => _pickDayFor(context, [for (final b in plan.overflow) b.itemId]),
                      ),
                    ]),
                  ],
                  if (plan.quick.isNotEmpty) ...[
                    _sectionTitle('Quick, any time'),
                    for (final b in plan.quick) _pieceCard(PlanBlock(b.title, _day, 0, itemId: b.itemId, reason: b.reason)),
                  ],
                  if (plan.standby.isNotEmpty) ...[
                    _sectionTitle('On standby'),
                    for (final b in plan.standby) _pieceCard(PlanBlock(b.title, _day, b.minutes, itemId: b.itemId, reason: b.reason), status: 'No time kept unless needed'),
                  ],
                  if (plan.off.isNotEmpty) ...[
                    _sectionTitle(_isToday ? 'Not today' : 'Not this day'),
                    for (final b in plan.off) _pieceCard(PlanBlock(b.title, _day, b.minutes, itemId: b.itemId, reason: b.reason), status: 'Waiting'),
                  ],
                  if (plan.skipped.isNotEmpty) ...[
                    _sectionTitle(_isToday ? 'Left out today' : 'Left out of this day'),
                    for (final b in plan.skipped)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(b.title),
                        trailing: TextButton(onPressed: () => setState(() => _edits.remove(b.itemId)), child: const Text('Add back')),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      );
}
