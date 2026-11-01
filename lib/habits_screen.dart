import 'package:flutter/material.dart';

import 'store.dart';

/// Asks for a habit name and weekly target. Returns the new habit, or null if cancelled.
Future<Rec?> showAddHabit(BuildContext context, Store store, {String name = ''}) {
  final nameCtrl = TextEditingController(text: name);
  var perWeek = 3;
  return showDialog<Rec>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('New habit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name, like gym')),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Times per week'),
                const Spacer(),
                IconButton(
                  onPressed: perWeek > 1 ? () => setS(() => perWeek--) : null,
                  icon: const Icon(Icons.remove),
                ),
                Text('$perWeek'),
                IconButton(
                  onPressed: perWeek < 7 ? () => setS(() => perWeek++) : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final n = nameCtrl.text.trim();
              if (n.isEmpty) return;
              Navigator.pop(ctx, store.addHabit(n, perWeek));
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}

class HabitsScreen extends StatelessWidget {
  const HabitsScreen({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () => showAddHabit(context, store),
          child: const Icon(Icons.add),
        ),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final today = dayKey(DateTime.now());
            final monday = store.mondayOf(DateTime.now());
            final habits = store.list('habits');
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Habits', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (habits.isEmpty) const Text('No habits yet. Add one, then just tell Jarvis when you do it.'),
                for (final h in habits)
                  Card(
                    child: ListTile(
                      title: Text(h['name'] as String),
                      subtitle: Text(
                        'This week ${store.weekCount(h, monday)}/${h['perWeek']}  ·  streak ${store.streakWeeks(h)} weeks',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Done today',
                            icon: Icon(
                              (h['logs'] as Rec)[today] == 'yes' ? Icons.check_circle : Icons.check_circle_outline,
                            ),
                            onPressed: () => store.logHabit(h, today, 'yes'),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => store.removeRec('habits', h, 'Deleted habit ${h['name']}'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
}
