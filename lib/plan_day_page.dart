import 'package:flutter/material.dart';

import 'day_planner.dart';
import 'haptics.dart';
import 'store.dart';
import 'task_sheet.dart';

/// Shows a proposed timeline for a day (today unless one is chosen). Tap a task to change its time, length,
/// time window or longest length, leave it out, or move it to another day. Add tasks by hand.
/// Apply gives each task its time, so the day is on the calendar and can be edited there.
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

class _PlanDayPageState extends State<PlanDayPage> {
  Store get store => widget.store;

  late DateTime _day = DateTime(widget.day?.year ?? DateTime.now().year, widget.day?.month ?? DateTime.now().month, widget.day?.day ?? DateTime.now().day);

  /// Changes made on this page; they are written to the tasks only on Apply.
  final _edits = <int, PlanEdit>{};

  /// Tasks added to this day by hand.
  final _extra = <int>{};

  /// Tasks planned earlier keep their time, unless Jarvis is asked to place them again.
  final _unpinned = <int>{};
  bool _replan = false;

  bool get _isToday => dayKey(_day) == dayKey(DateTime.now());

  /// The plan for [day] (this page's day when null), with [extra] added to it.
  DayPlan _plan({DateTime? day, Set<int>? extra}) {
    final now = DateTime.now();
    final d = day ?? _day;
    final key = dayKey(d);
    final all = store.list('items').cast<Map<String, dynamic>>();
    // A habit's planned task from an earlier day is stale: the day gets a fresh one.
    final open = all.where((i) => i['status'] == 'open' && (i['planHabit'] == null || i['habitDay'] == key)).toList();
    final habits = DayPlanner.habitTasks(store.list('habits').cast<Map<String, dynamic>>(), d, items: all);
    // A habit with a reminder time (later today, or on another day) starts at that time, unless you moved it.
    final pins = <int, PlanEdit>{
      for (final t in habits)
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
    return DayPlanner.plan(
      now: now,
      day: d,
      extra: extra ?? _extra,
      items: [...open, ...habits, ...store.phoneEvents],
      ratios: ratios,
      edits: {...kept, ...pins, ..._edits},
    );
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
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Planned. It is on the calendar now, and you will get a reminder as each one starts.')));
      Navigator.pop(context);
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

  /// Open tasks that are not on this day's plan yet, to add by hand.
  Future<void> _addTasks(BuildContext context, DayPlan plan) async {
    final onPlan = {
      for (final b in [...plan.blocks, ...plan.overflow, ...plan.skipped, ...plan.quick]) b.itemId,
    };
    final choices = store
        .list('items')
        .where((i) => i['kind'] == 'task' && i['status'] == 'open' && i['planHabit'] == null && !onPlan.contains(i['id']))
        .toList()
      ..sort((a, b) => ((a['when'] as int?) ?? 1 << 60).compareTo((b['when'] as int?) ?? 1 << 60));
    final picked = <int>{};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text('Add to ${_dayName(_day)}', style: Theme.of(ctx).textTheme.titleLarge),
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('New task'),
                onTap: () {
                  Navigator.pop(ctx);
                  showTaskSheet(context, store);
                },
              ),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  if (choices.isEmpty) const ListTile(title: Text('No other open tasks.')),
                  for (final i in choices)
                    CheckboxListTile(
                      value: picked.contains(i['id']),
                      title: Text('${i['title']}'),
                      subtitle: Text([
                        if (i['when'] is int) 'dated ${_dayName(DateTime.fromMillisecondsSinceEpoch(i['when'] as int))}' else 'no date',
                        if (i['est'] != null) fmtMinutes(i['est'] as int),
                      ].join('  ·  ')),
                      onChanged: (v) => setS(() => v == true ? picked.add(i['id'] as int) : picked.remove(i['id'])),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton(
                  onPressed: picked.isEmpty
                      ? null
                      : () {
                          setState(() => _extra.addAll(picked));
                          Navigator.pop(ctx);
                        },
                  child: Text(picked.isEmpty ? 'Add' : 'Add ${picked.length}'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  bool _hasWindow(int? id) {
    if (_edits[id]?.noWindow == true) return false;
    final it = store.byId('items', id);
    return _edits[id]?.from != null || _edits[id]?.to != null || it?['winFrom'] != null || it?['winTo'] != null;
  }

  bool _changed(int? id) => _edits[id]?.start != null || _edits[id]?.minutes != null;

  void _change(int id, PlanEdit Function(PlanEdit) f) => setState(() => _edits[id] = f(_edits[id] ?? const PlanEdit()));

  Future<void> _adjust(BuildContext context, PlanBlock b) async {
    final id = b.itemId;
    final it = id == null ? null : store.byId('items', id);
    if (id == null || (it == null && id > 0)) return; // a habit's time has a negative id and no task yet
    if (b.fixed && it != null) return showTaskSheet(context, store, item: it);
    var start = b.start;
    var minutes = b.minutes;
    final own = _edits[id];
    int? from = own?.noWindow == true ? null : (own?.from ?? (it?['winFrom'] as num?)?.toInt());
    int? to = own?.noWindow == true ? null : (own?.to ?? (it?['winTo'] as num?)?.toInt());
    int? most = own?.max ?? (it?['estMax'] as num?)?.toInt();
    Future<int?> pickTime(BuildContext ctx, int? at) async {
      final t = await showTimePicker(context: ctx, initialTime: TimeOfDay(hour: (at ?? 540) ~/ 60, minute: (at ?? 540) % 60));
      return t == null ? null : t.hour * 60 + t.minute;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.title, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule),
                label: Text('Starts ${clock(start.millisecondsSinceEpoch)}'),
                onPressed: () async {
                  final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(start));
                  if (t == null) return;
                  setS(() => start = DateTime(start.year, start.month, start.day, t.hour, t.minute));
                  _change(id, (e) => e.copyWith(start: start));
                },
              ),
              const SizedBox(height: 16),
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
                Expanded(child: Center(child: Text(fmtMinutes(minutes), style: Theme.of(ctx).textTheme.titleMedium))),
                IconButton.filledTonal(
                  tooltip: 'Longer',
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    setS(() => minutes += minutes >= 60 ? 15 : 5);
                    _change(id, (e) => e.copyWith(minutes: minutes));
                  },
                ),
              ]),
              Wrap(spacing: 8, children: [
                for (final m in [15, 30, 45, 60, 90, 120])
                  ChoiceChip(
                    label: Text(fmtMinutes(m)),
                    selected: minutes == m,
                    onSelected: (_) {
                      setS(() => minutes = m);
                      _change(id, (e) => e.copyWith(minutes: m));
                    },
                  ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                IconButton.filledTonal(
                  tooltip: 'Fixed length',
                  icon: const Icon(Icons.remove),
                  onPressed: most == null || most! <= minutes
                      ? null
                      : () {
                          setS(() => most = most! - (most! > 60 ? 15 : 5));
                          _change(id, (e) => e.copyWith(max: most));
                        },
                ),
                Expanded(
                  child: Center(
                    child: Text(most == null || most! <= minutes ? 'Fixed length' : 'Can take up to ${fmtMinutes(most!)}',
                        style: Theme.of(ctx).textTheme.titleSmall),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Can take longer',
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    setS(() => most = (most == null || most! < minutes ? minutes : most!) + (minutes >= 60 ? 15 : 5));
                    _change(id, (e) => e.copyWith(max: most));
                  },
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    child: Text(from == null ? 'Not before: any time' : 'Not before ${_hm(from!)}'),
                    onPressed: () async {
                      final m = await pickTime(ctx, from);
                      if (m == null) return;
                      setS(() => from = m);
                      _change(id, (e) => e.copyWith(from: m, noWindow: false));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    child: Text(to == null ? 'Done by: any time' : 'Done by ${_hm(to!)}'),
                    onPressed: () async {
                      final m = await pickTime(ctx, to);
                      if (m == null) return;
                      setS(() => to = m);
                      _change(id, (e) => e.copyWith(to: m, noWindow: false));
                    },
                  ),
                ),
              ]),
              if (from != null || to != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    child: const Text('Any time of day'),
                    onPressed: () {
                      setS(() {
                        from = null;
                        to = null;
                      });
                      _change(id, (e) => e.copyWith(noWindow: true));
                    },
                  ),
                ),
              const SizedBox(height: 8),
              if (it != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Quick, no time block'),
                  subtitle: const Text('Like a call or a payment: listed apart, done any time'),
                  value: false,
                  onChanged: (_) {
                    Navigator.pop(ctx);
                    _edits.remove(id);
                    store.updateRec('items', it, '${it['title']}: quick', (r) => r['quick'] = true);
                  },
                ),
              Wrap(spacing: 8, children: [
                if (it != null)
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit task'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      showTaskSheet(context, store, item: it);
                    },
                  ),
                if (_edits[id]?.start != null || (it?['planned'] == dayKey(_day) && !_unpinned.contains(id) && !_replan))
                  TextButton.icon(
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Let Jarvis place it'),
                    onPressed: () {
                      _unpinned.add(id);
                      _change(id, (e) => e.copyWith(clearStart: true));
                      Navigator.pop(ctx);
                    },
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.event_busy),
                  label: Text(_isToday ? 'Leave out today' : 'Leave out of this day'),
                  onPressed: () {
                    _change(id, (e) => e.copyWith(skip: true));
                    Navigator.pop(ctx);
                  },
                ),
              ]),
              if (it != null) ...[
                const SizedBox(height: 8),
                Text('Do it on another day', style: Theme.of(ctx).textTheme.titleSmall),
                Wrap(spacing: 8, children: [
                  for (final (label, days) in [('Tomorrow', 1), ('In 3 days', 3), ('Next week', 7)])
                    ActionChip(
                      label: Text(label),
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
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Plan a day'),
          actions: [
            if (_edits.isNotEmpty || _unpinned.isNotEmpty || _replan || _extra.isNotEmpty)
              TextButton(
                onPressed: () => setState(() {
                  _edits.clear();
                  _unpinned.clear();
                  _extra.clear();
                  _replan = false;
                }),
                child: const Text('Reset changes'),
              ),
          ],
        ),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final plan = _plan();
            final scheme = Theme.of(context).colorScheme;
            final tasks = plan.blocks.where((b) => !b.fixed).length;
            final busy = plan.blocks.fold<int>(0, (a, b) => a + b.minutes);
            final room = _nextRoom(plan);
            final planned = plan.blocks.any((b) => !b.fixed && store.byId('items', b.itemId)?['planned'] == dayKey(_day));
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Row(children: [
                  IconButton(tooltip: 'Previous day', icon: const Icon(Icons.chevron_left), onPressed: () => _goTo(DateTime(_day.year, _day.month, _day.day - 1))),
                  Expanded(
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
                      child: Text(_dayName(_day), style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ),
                  IconButton(tooltip: 'Next day', icon: const Icon(Icons.chevron_right), onPressed: () => _goTo(DateTime(_day.year, _day.month, _day.day + 1))),
                ]),
                Text(
                  tasks == 0 && plan.overflow.isEmpty
                      ? 'Nothing planned for ${_isToday ? 'today' : 'this day'} yet. Add the tasks you want to do.'
                      : '$tasks task${tasks == 1 ? '' : 's'} fit, ${fmtMinutes(busy)} in all, with 10 minute breaks. '
                          'Tap one to set a time window, a longest length, or another day.',
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 8, children: [
                    TextButton.icon(icon: const Icon(Icons.playlist_add), label: const Text('Add tasks'), onPressed: () => _addTasks(context, plan)),
                    if (planned)
                      TextButton.icon(
                        icon: const Icon(Icons.auto_fix_high),
                        label: const Text('Place everything again'),
                        onPressed: () => setState(() => _replan = true),
                      ),
                  ]),
                ),
                const SizedBox(height: 4),
                for (final b in plan.blocks)
                  Card(
                    color: b.fixed ? scheme.surfaceContainerHighest : null,
                    child: ListTile(
                      leading: Icon(
                        b.fixed ? Icons.event : ((b.itemId ?? 0) < 0 || store.byId('items', b.itemId)?['planHabit'] != null ? Icons.local_fire_department_outlined : Icons.check_box_outline_blank),
                        color: b.fixed ? null : scheme.primary,
                      ),
                      title: Text(b.title),
                      subtitle: Text('${clock(b.start.millisecondsSinceEpoch)} – ${clock(b.end.millisecondsSinceEpoch)}  ·  ${fmtMinutes(b.minutes)}'
                          '${b.fixed ? '  ·  already planned' : ''}${_changed(b.itemId) ? '  ·  changed' : ''}'
                          '${!b.fixed && _hasWindow(b.itemId) ? '  ·  has a time window' : ''}'),
                      trailing: const Icon(Icons.tune),
                      onTap: () => _adjust(context, b),
                    ),
                  ),
                if (plan.overflow.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_isToday ? "Doesn't fit today" : "Doesn't fit this day", style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.error)),
                  for (final b in plan.overflow)
                    ListTile(
                      dense: true,
                      title: Text(b.title),
                      subtitle: b.reason == null ? null : Text(b.reason!),
                      trailing: Text(fmtMinutes(b.minutes)),
                      onTap: () => _adjust(context, PlanBlock(b.title, _day, b.minutes, itemId: b.itemId)),
                    ),
                  Wrap(spacing: 8, children: [
                    if (room != null)
                      TextButton.icon(
                        icon: const Icon(Icons.redo),
                        label: Text('Move these to ${_dayName(room)} (they fit)'),
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
                  const SizedBox(height: 12),
                  Text('Quick, any time', style: Theme.of(context).textTheme.titleSmall),
                  Text('No block needed. Tick them off when done.', style: TextStyle(color: scheme.onSurfaceVariant)),
                  for (final b in plan.quick)
                    Builder(builder: (context) {
                      final it = store.byId('items', b.itemId);
                      if (it == null) return const SizedBox.shrink();
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Checkbox(
                          value: false,
                          onChanged: (_) {
                            Haptics.success();
                            store.markDone(it);
                          },
                        ),
                        title: Text(b.title),
                        trailing: TextButton(
                          onPressed: () => store.updateRec('items', it, '${it['title']}: needs time', (r) => r['quick'] = false),
                          child: const Text('Needs time'),
                        ),
                      );
                    }),
                ],
                if (plan.skipped.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_isToday ? 'Left out today' : 'Left out of this day', style: Theme.of(context).textTheme.titleSmall),
                  for (final b in plan.skipped)
                    ListTile(
                      dense: true,
                      title: Text(b.title),
                      trailing: TextButton(
                        onPressed: () => setState(() => _edits.remove(b.itemId)),
                        child: const Text('Add back'),
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                if (tasks > 0)
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Apply this plan'),
                    onPressed: () => _apply(context, plan),
                  ),
              ],
            );
          },
        ),
      );
}
