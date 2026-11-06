import 'package:flutter/material.dart';

import 'day_planner.dart';
import 'haptics.dart';
import 'store.dart';

/// Shows a proposed timeline for today. Apply gives each task its time; what does not fit can go to tomorrow.
class PlanDayPage extends StatelessWidget {
  const PlanDayPage({super.key, required this.store});
  final Store store;

  DayPlan _plan() {
    final open = store.list('items').where((i) => i['status'] == 'open').toList();
    final ratios = <String, double>{
      for (final i in open)
        if (i['cat'] != null && store.estimateSuggestion(i['cat'] as String, 60) != null)
          i['cat'] as String: store.estimateSuggestion(i['cat'] as String, 60)!.ratio,
    };
    return DayPlanner.plan(now: DateTime.now(), items: open, ratios: ratios);
  }

  Future<void> _apply(BuildContext context, DayPlan plan) async {
    Haptics.success();
    final undo = <Rec>[];
    for (final b in plan.blocks.where((b) => !b.fixed)) {
      final it = store.byId('items', b.itemId);
      if (it == null) continue;
      undo.add({'op': 'put', 'col': 'items', 'rec': copyRec(it)});
      it['when'] = b.start.millisecondsSinceEpoch;
      it['allDay'] = false;
      it['est'] ??= b.minutes;
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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Plan my day')),
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
                      leading: Icon(b.fixed ? Icons.event : Icons.check_box_outline_blank, color: b.fixed ? null : scheme.primary),
                      title: Text(b.title),
                      subtitle: Text('${clock(b.start.millisecondsSinceEpoch)} – ${clock(b.end.millisecondsSinceEpoch)}  ·  ${fmtMinutes(b.minutes)}'
                          '${b.fixed ? '  ·  already planned' : ''}'),
                    ),
                  ),
                if (plan.overflow.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text("Doesn't fit today", style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.error)),
                  for (final b in plan.overflow) ListTile(dense: true, title: Text(b.title), trailing: Text(fmtMinutes(b.minutes))),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.redo),
                      label: const Text('Move these to tomorrow'),
                      onPressed: () => _moveRest(context, plan),
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
