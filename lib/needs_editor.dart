import 'package:flutter/material.dart';

import 'haptics.dart';
import 'needs.dart';
import 'piece_facts.dart';
import 'store.dart';

/// Picks a task or habit to link to: returns the piece (a task's id, minus a habit's id) and whether
/// it should be done (false: not done). [self] is left out of the list.
Future<({int id, bool not})?> pickPiece(BuildContext context, Store s, {required bool habits, int? self}) {
  final list = habits
      ? [for (final h in s.orderedHabits()) (id: -(h['id'] as int), title: '${h['name']}')]
      : [
          for (final i in s.list('items'))
            if (i['kind'] == 'task' && i['status'] == 'open' && i['planHabit'] == null && i['partOf'] == null) (id: i['id'] as int, title: '${i['title']}'),
        ];
  list.removeWhere((p) => p.id == self);
  return showModalBottomSheet<({int id, bool not})>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(habits ? 'Which habit?' : 'Which task?', style: Theme.of(ctx).textTheme.titleLarge),
          ),
          if (list.isEmpty)
            Padding(padding: const EdgeInsets.all(20), child: Text(habits ? 'No habits yet.' : 'No other open tasks.')),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final p in list)
                ListTile(
                  leading: Icon(habits ? Icons.local_fire_department_outlined : Icons.check_box_outline_blank),
                  title: Text(p.title),
                  onTap: () async {
                    final not = await pickDone(ctx, p.title);
                    if (not != null && ctx.mounted) Navigator.pop(ctx, (id: p.id, not: not));
                  },
                ),
            ]),
          ),
        ]),
      ),
    ),
  );
}

/// "Only if [title] is done" or "is not done". Returns whether it is the "not" one.
Future<bool?> pickDone(BuildContext context, String title) => showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: Text('Only if "$title" is done'),
            subtitle: const Text('It comes after, and stays quiet until then'),
            onTap: () => Navigator.pop(ctx, false),
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: Text('Only if "$title" is not done'),
            subtitle: const Text('A fallback: it comes in if that one is missed'),
            onTap: () => Navigator.pop(ctx, true),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );

/// A money condition: an account with at least, or under, an amount.
Future<Map<String, dynamic>?> pickBalance(BuildContext context, Store s) {
  final accounts = [for (final a in s.list('accounts')) '${a['name']}'];
  var account = accounts.contains('Cash') ? 'Cash' : (accounts.isEmpty ? 'Cash' : accounts.first);
  var atLeast = true;
  final amount = TextEditingController();
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Only if there is money'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: account,
            decoration: const InputDecoration(labelText: 'Account'),
            items: [for (final a in accounts.isEmpty ? ['Cash'] : accounts) DropdownMenuItem(value: a, child: Text(a))],
            onChanged: (v) => setS(() => account = v ?? account),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('Has at least'), selected: atLeast, onSelected: (_) => setS(() => atLeast = true)),
            ChoiceChip(label: const Text('Has under'), selected: !atLeast, onSelected: (_) => setS(() => atLeast = false)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Amount', prefixText: '${s.settings['currency'] ?? ''} '),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = num.tryParse(amount.text.trim());
              if (v == null) return;
              Navigator.pop(ctx, {'check': 'balance', 'account': account, atLeast ? 'atLeast' : 'below': v});
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}

/// A countdown condition: while it is still running, or once it has ended.
Future<Map<String, dynamic>?> pickCountdown(BuildContext context, Store s) => showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final list = s.list('countdowns');
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: ListView(shrinkWrap: true, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Which countdown?', style: Theme.of(ctx).textTheme.titleLarge),
              ),
              if (list.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('No countdowns yet. Add one in More, Countdowns.')),
              for (final c in list) ...[
                ListTile(
                  leading: const Icon(Icons.hourglass_top),
                  title: Text('Until "${c['title']}" ends'),
                  subtitle: const Text('Only while it is still running'),
                  onTap: () => Navigator.pop(ctx, {'check': 'countdown', 'id': c['id']}),
                ),
                ListTile(
                  leading: const Icon(Icons.hourglass_bottom),
                  title: Text('After "${c['title']}" ends'),
                  onTap: () => Navigator.pop(ctx, {'check': 'countdown', 'id': c['id'], 'not': true}),
                ),
              ],
            ]),
          ),
        );
      },
    );

/// Shows a piece's links and conditions as chips, and adds or removes them.
/// [needs] is `{any, if: [check]}` or null; [onChanged] gets the new one (null when the last is removed).
class NeedsEditor extends StatelessWidget {
  const NeedsEditor({super.key, required this.store, required this.needs, required this.onChanged, this.self});
  final Store store;
  final Object? needs;
  final ValueChanged<Map<String, dynamic>?> onChanged;

  /// The piece being edited, so it cannot depend on itself.
  final int? self;

  void _set(List<Map> checks, {bool? any}) {
    Haptics.tap();
    onChanged(checks.isEmpty
        ? null
        : {'any': any ?? (needs is Map && (needs as Map)['any'] == true), 'if': [for (final c in checks) Map<String, dynamic>.from(c)]});
  }

  @override
  Widget build(BuildContext context) {
    final checks = Needs.checks(needs);
    final any = needs is Map && (needs as Map)['any'] == true;
    final facts = PieceFacts(store);
    Future<void> add(Future<Map<String, dynamic>?> Function() pick) async {
      final c = await pick();
      if (c != null) _set([...checks, c]);
    }

    Future<Map<String, dynamic>?> piece(bool habits) async {
      final p = await pickPiece(context, store, habits: habits, self: self);
      return p == null ? null : {'check': 'done', 'id': p.id, if (p.not) 'not': true};
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (checks.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('All of these'), selected: !any, onSelected: (_) => _set(checks, any: false)),
            ChoiceChip(label: const Text('Any of these'), selected: any, onSelected: (_) => _set(checks, any: true)),
          ]),
        ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in checks)
          InputChip(
            label: Text(Needs.sentence(c, name: facts.name, money: store.money)),
            onDeleted: () => _set([...checks]..remove(c)),
          ),
        ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Task'), onPressed: () => add(() => piece(false))),
        ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Habit'), onPressed: () => add(() => piece(true))),
        ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Money'), onPressed: () => add(() => pickBalance(context, store))),
        ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Countdown'), onPressed: () => add(() => pickCountdown(context, store))),
      ]),
    ]);
  }
}
