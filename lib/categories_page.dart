import 'package:flutter/material.dart';

import 'categories.dart';
import 'haptics.dart';
import 'store.dart';

/// Merge or rename money categories. Merging teaches Jarvis: the next "groceries" you type, say or import
/// lands in the category you merged it into.
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, required this.store});
  final Store store;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  var _type = 'expense';

  Store get s => widget.store;

  Future<void> _merge(CatUse from, List<CatUse> all) async {
    final to = TextEditingController();
    final others = all.where((u) => Cats.key(u.name) != Cats.key(from.name)).toList();
    final target = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final name = to.text.trim();
          final exists = others.any((u) => Cats.key(u.name) == Cats.key(name));
          return AlertDialog(
            title: Text('Merge or rename "${from.name}"'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${from.count} ${from.count == 1 ? 'entry' : 'entries'} move there, and Jarvis files "${from.name}" under it from now on.'),
                const SizedBox(height: 12),
                if (others.isNotEmpty)
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final u in others)
                      ChoiceChip(label: Text(u.name), selected: name == u.name, onSelected: (_) => setD(() => to.text = u.name)),
                  ]),
                TextField(
                  controller: to,
                  onChanged: (_) => setD(() {}),
                  decoration: const InputDecoration(labelText: 'Merge into, or a new name'),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: name.isEmpty || Cats.key(name) == Cats.key(from.name) ? null : () => Navigator.pop(ctx, name),
                child: Text(exists ? 'Merge' : 'Rename'),
              ),
            ],
          );
        },
      ),
    );
    if (target == null) return;
    // Use the spelling already in use if the name matches one.
    final spelled = all.where((u) => Cats.key(u.name) == Cats.key(target)).map((u) => u.name).firstOrNull ?? target.trim();
    Haptics.success();
    await s.mergeCategory(_type, from.name, spelled);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final tt = Theme.of(context).textTheme;
          final scheme = Theme.of(context).colorScheme;
          final used = Cats.used(s.list('tx').cast<Map<String, dynamic>>(), _type);
          final twins = Cats.lookAlikes(used);
          final rules = s.catRules.entries.where((e) => e.key.startsWith('$_type:')).toList()..sort((a, b) => a.key.compareTo(b.key));
          return Scaffold(
            appBar: AppBar(title: const Text('Tidy categories')),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'expense', label: Text('Expenses')),
                    ButtonSegment(value: 'income', label: Text('Income')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (v) => setState(() => _type = v.first),
                ),
                const SizedBox(height: 12),
                for (final g in twins)
                  Card(
                    color: scheme.primaryContainer,
                    child: ListTile(
                      title: Text('${g.map((u) => '"${u.name.trim()}"').join(' and ')} look the same'),
                      subtitle: Text('${g.fold<int>(0, (a, u) => a + u.count)} entries'),
                      trailing: FilledButton(
                        onPressed: () async {
                          Haptics.success();
                          for (final u in g.skip(1)) {
                            await s.mergeCategory(_type, u.name, g.first.name);
                          }
                        },
                        child: Text('Merge into ${g.first.name.trim()}'),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: Text('Tap a category to merge it into another or rename it.', style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ),
                if (used.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No entries yet.')),
                for (final u in used)
                  Card(
                    child: ListTile(
                      title: Text(u.name),
                      subtitle: Text('${u.count} ${u.count == 1 ? 'entry' : 'entries'}  ·  ${s.money(u.total)}'),
                      trailing: const Icon(Icons.merge_type),
                      onTap: u.name == 'Transfer' ? null : () => _merge(u, used),
                    ),
                  ),
                if (rules.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
                    child: Text('Jarvis files these automatically', style: tt.titleSmall?.copyWith(color: scheme.primary)),
                  ),
                  for (final r in rules)
                    ListTile(
                      dense: true,
                      title: Text('${r.key.substring(_type.length + 1)}  →  ${r.value}'),
                      trailing: IconButton(
                        tooltip: 'Stop doing this',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          s.catRules.remove(r.key);
                          s.save();
                          setState(() {});
                        },
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      );
}
