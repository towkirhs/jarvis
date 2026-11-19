import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'budgets.dart';
import 'categories.dart';
import 'haptics.dart';
import 'store.dart';

/// The top of Money's Daily tab: what you still have to buy (with its total against your cash) and
/// this month's budgets. Both are quiet when there is nothing to show.
class MoneyPlanCards extends StatelessWidget {
  const MoneyPlanCards({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    final s = store;
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final buy = Budgets.toBuy(s.list('items'));
    final total = buy.fold<num>(0, (a, i) => a + ((i['cost'] as num?) ?? 0));
    final cash = s.list('accounts').where((a) => '${a['name']}'.toLowerCase() == 'cash').firstOrNull;
    final have = cash == null ? null : s.balance(cash);
    final rows = Budgets.month(s.list('tx'), Budgets.of(s.settings), DayStart.now());

    Widget card(List<Widget> children) => Card(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        );

    return Column(children: [
      if (buy.isNotEmpty)
        card([
          Row(children: [
            Expanded(child: Text('To buy · ${buy.length}', style: tt.titleSmall)),
            if (total > 0)
              Text(
                have == null ? s.money(total) : '${s.money(total)} of ${s.money(have)} cash',
                style: tt.bodySmall?.copyWith(color: have != null && total > have ? scheme.error : scheme.onSurfaceVariant),
              ),
          ]),
          const SizedBox(height: 4),
          for (final i in buy.take(6))
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: false,
              title: Text('${i['title']}'),
              secondary: i['cost'] is num ? Text(s.money(i['cost'] as num)) : TextButton(onPressed: () => _askCost(context, s, i), child: const Text('Price')),
              // Ticking it off asks "Paid ৳X?" (when it has a price), like anywhere else.
              onChanged: (_) {
                Haptics.success();
                s.markDone(i);
              },
            ),
          if (buy.length > 6) Text('and ${buy.length - 6} more', style: TextStyle(color: scheme.onSurfaceVariant)),
        ]),
      card([
        Row(children: [
          Expanded(child: Text(rows.isEmpty ? 'Budgets' : 'Budgets this month', style: tt.titleSmall)),
          TextButton(onPressed: () => showBudgetsSheet(context, s), child: Text(rows.isEmpty ? 'Set a budget' : 'Change')),
        ]),
        if (rows.isEmpty)
          Text('Give a category a monthly limit, and Jarvis warns you at 80% and when it is used up.',
              style: TextStyle(color: scheme.onSurfaceVariant))
        else
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(r.category)),
                  Text(
                    r.left >= 0 ? '${s.money(r.left)} left' : '${s.money(-r.left)} over',
                    style: tt.bodySmall?.copyWith(color: r.ratio >= 1 ? scheme.error : scheme.onSurfaceVariant),
                  ),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: r.ratio.clamp(0, 1).toDouble(),
                    minHeight: 6,
                    color: r.ratio >= 1 ? scheme.error : (r.ratio >= 0.8 ? scheme.tertiary : scheme.primary),
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ]),
            ),
      ]),
    ]);
  }

  static Future<void> _askCost(BuildContext context, Store s, Rec it) async {
    final ctrl = TextEditingController();
    final v = await showDialog<num>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Price of ${it['title']}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: const InputDecoration(prefixText: '৳ '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, num.tryParse(ctrl.text)), child: const Text('Save')),
        ],
      ),
    );
    if (v != null && v > 0) await s.updateRec('items', it, '${it['title']}: costs ৳${v.round()}', (r) => r['cost'] = v);
  }
}

/// Monthly budgets per expense category, and the evening cash check.
Future<void> showBudgetsSheet(BuildContext context, Store s) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ListenableBuilder(
        listenable: s,
        builder: (ctx, _) {
          final tt = Theme.of(ctx).textTheme;
          final scheme = Theme.of(ctx).colorScheme;
          final budgets = Budgets.of(s.settings);
          final cats = {...budgets.keys, for (final u in Cats.used(s.list('tx'), 'expense')) u.name}.toList();
          final at = (s.settings['cashAt'] as String?) ?? '21:30';
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
                Text('Budgets', style: tt.headlineSmall),
                const SizedBox(height: 4),
                Text('A monthly limit per category. Leave empty for none.', style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                if (cats.isEmpty) Text('No spending yet to set budgets for.', style: TextStyle(color: scheme.onSurfaceVariant)),
                for (final c in cats)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      Expanded(child: Text(c)),
                      SizedBox(
                        width: 130,
                        child: TextFormField(
                          initialValue: budgets[c]?.round().toString() ?? '',
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(prefixText: '৳ ', hintText: 'none', isDense: true),
                          onChanged: (v) => s.setBudget(c, num.tryParse(v)),
                        ),
                      ),
                    ]),
                  ),
                const SizedBox(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Evening cash check'),
                  subtitle: Text('Every day at ${clock(DateTime(2000, 1, 1, int.parse(at.split(':')[0]), int.parse(at.split(':')[1])).millisecondsSinceEpoch)}: '
                      '"Cash ৳X, right?" Right, or Fix to type the real amount.'),
                  value: s.settings['cashCheck'] != false,
                  onChanged: (v) {
                    s.settings['cashCheck'] = v;
                    s.save();
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: const Text('Change the time'),
                    onPressed: () async {
                      final p = at.split(':');
                      final t = await showTimePicker(context: ctx, initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])));
                      if (t == null) return;
                      s.settings['cashAt'] = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                      s.save();
                    },
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
              ]),
            ),
          );
        },
      ),
    );
