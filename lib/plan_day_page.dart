import 'package:flutter/material.dart';

import 'day_planner.dart';
import 'haptics.dart';
import 'store.dart';
import 'task_sheet.dart';

/// Shows a proposed timeline for today. Tap a task to change its time or length, leave it out, or edit it.
/// Apply gives each task its time; what does not fit can go to tomorrow.
class PlanDayPage extends StatefulWidget {
  const PlanDayPage({super.key, required this.store});
  final Store store;

  @override
  State<PlanDayPage> createState() => _PlanDayPageState();
}

class _PlanDayPageState extends State<PlanDayPage> {
  Store get store => widget.store;

  /// Changes made on this page; they are written to the tasks only on Apply.
  final _edits = <int, PlanEdit>{};

  DayPlan _plan() {
    final now = DateTime.now();
    final today = dayKey(now);
    // A habit's planned task from an earlier day is stale: today gets a fresh one.
    final open = store.list('items').where((i) => i['status'] == 'open' && (i['planHabit'] == null || i['habitDay'] == today)).toList();
    final habits = DayPlanner.habitTasks(store.list('habits').cast<Map<String, dynamic>>(), now, items: store.list('items').cast<Map<String, dynamic>>());
    // A habit with a reminder time later today starts at that time, unless you moved it.
    final pins = <int, PlanEdit>{
      for (final t in habits)
        if (_remindToday(store.byId('habits', t['habitId'] as int), now) case final at?) t['id'] as int: PlanEdit(start: at),
    };
    final ratios = <String, double>{
      for (final i in open)
        if (i['cat'] != null && store.estimateSuggestion(i['cat'] as String, 60) != null)
          i['cat'] as String: store.estimateSuggestion(i['cat'] as String, 60)!.ratio,
    };
    return DayPlanner.plan(now: now, items: [...open, ...habits], ratios: ratios, edits: {...pins, ..._edits});
  }

  DateTime? _remindToday(Rec? h, DateTime now) {
    final r = h?['remind'] as String?;
    if (r == null) return null;
    final p = r.split(':');
    final at = DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
    return at.isAfter(now) ? at : null;
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
        extra: {'planHabit': -b.itemId!, 'habitDay': dayKey(DateTime.now()), 'list': 'Habits', 'allDay': false, 'quick': false},
      );
    }
    for (final b in plan.blocks.where((b) => !b.fixed && (b.itemId ?? 0) > 0)) {
      final it = store.byId('items', b.itemId);
      if (it == null) continue;
      undo.add({'op': 'put', 'col': 'items', 'rec': copyRec(it)});
      it['when'] = b.start.millisecondsSinceEpoch;
      it['allDay'] = false;
      if (_edits[b.itemId]?.minutes != null) {
        it['est'] = b.minutes;
      } else {
        it['est'] ??= b.minutes;
      }
      it['nid'] ??= store.nextId();
      await store.syncRecord('items', it);
    }
    store.logAction('Planned the day (${undo.length} tasks)', undo);
    store.save();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Planned. You will get a reminder as each one starts.')));
      Navigator.pop(context);
    }
  }

  Future<void> _moveRest(BuildContext context, DayPlan plan) async {
    final now = DateTime.now();
    final undo = <Rec>[];
    for (final b in plan.overflow) {
      final it = store.byId('items', b.itemId);
      if (it == null) continue;
      undo.add({'op': 'put', 'col': 'items', 'rec': copyRec(it)});
      it['when'] = DateTime(now.year, now.month, now.day + 1, 9).millisecondsSinceEpoch;
      it['allDay'] = true;
      it['postponed'] = ((it['postponed'] as int?) ?? 0) + 1;
      await store.syncRecord('items', it);
    }
    store.logAction('Moved ${undo.length} tasks to tomorrow', undo);
    store.save();
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
              const SizedBox(height: 12),
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
                if (_edits[id]?.start != null)
                  TextButton.icon(
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Let Jarvis place it'),
                    onPressed: () {
                      _change(id, (e) => e.copyWith(clearStart: true));
                      Navigator.pop(ctx);
                    },
                  ),
                TextButton.icon(
                  icon: const Icon(Icons.event_busy),
                  label: const Text('Leave out today'),
                  onPressed: () {
                    _change(id, (e) => e.copyWith(skip: true));
                    Navigator.pop(ctx);
                  },
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Plan my day'),
          actions: [
            if (_edits.isNotEmpty) TextButton(onPressed: () => setState(_edits.clear), child: const Text('Reset changes')),
          ],
        ),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final plan = _plan();
            final scheme = Theme.of(context).colorScheme;
            final tasks = plan.blocks.where((b) => !b.fixed).length;
            final busy = plan.blocks.fold<int>(0, (a, b) => a + b.minutes);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  tasks == 0 && plan.overflow.isEmpty
                      ? 'Nothing to plan: no open tasks for today.'
                      : '$tasks task${tasks == 1 ? '' : 's'} fit today, ${fmtMinutes(busy)} in all. '
                          'Times include how long you usually take, and 10 minute breaks.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
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
                          '${b.fixed ? '  ·  already planned' : ''}${_changed(b.itemId) ? '  ·  changed' : ''}'),
                      trailing: const Icon(Icons.tune),
                      onTap: () => _adjust(context, b),
                    ),
                  ),
                if (plan.overflow.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text("Doesn't fit today", style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.error)),
                  for (final b in plan.overflow)
                    ListTile(
                      dense: true,
                      title: Text(b.title),
                      trailing: Text(fmtMinutes(b.minutes)),
                      onTap: () => _adjust(context, PlanBlock(b.title, DateTime.now(), b.minutes, itemId: b.itemId)),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.redo),
                      label: const Text('Move these to tomorrow'),
                      onPressed: () => _moveRest(context, plan),
                    ),
                  ),
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
                  Text('Left out today', style: Theme.of(context).textTheme.titleSmall),
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
