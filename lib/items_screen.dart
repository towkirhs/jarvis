import 'package:flutter/material.dart';

import 'store.dart';

class ItemsScreen extends StatelessWidget {
  const ItemsScreen({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final open = store.list('items').where((i) => i['status'] == 'open').toList()
            ..sort((a, b) {
              final x = a['when'] as int?;
              final y = b['when'] as int?;
              if (x == null && y == null) return 0;
              if (x == null) return 1;
              if (y == null) return -1;
              return x.compareTo(y);
            });
          final done = store.list('items').where((i) => i['status'] == 'done').toList().reversed.take(10).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Plan', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (open.isEmpty) const Text('Nothing open. Tell Jarvis what is coming up.'),
              for (final it in open) _tile(it),
              if (done.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Recently done', style: Theme.of(context).textTheme.titleMedium),
                for (final it in done)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(it['title'] as String),
                    subtitle: it['actual'] == null ? null : Text('Took ${it['actual']} min'),
                  ),
              ],
            ],
          );
        },
      );

  Widget _tile(Rec it) {
    final w = it['when'] as int?;
    final est = it['est'] as int?;
    final postponed = (it['postponed'] as int?) ?? 0;
    final started = it['startedAt'] != null;
    final sug = store.estimateSuggestion(it['cat'] as String?, est);
    final icon = it['kind'] == 'task'
        ? Icons.check_box_outline_blank
        : (it['kind'] == 'alarm' ? Icons.alarm : Icons.event);
    final details = [
      if (w != null) niceWhen(w),
      if (est != null) '$est min',
      if (postponed > 0) 'postponed ${postponed}x',
      if (started) 'started',
    ].join('  ·  ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (details.isNotEmpty) Text(details),
                    ],
                  ),
                ),
                if (it['kind'] == 'task' && !started)
                  IconButton(
                    tooltip: 'Start',
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => store.updateRec(
                      'items', it, 'Started: ${it['title']}',
                      (r) => r['startedAt'] = DateTime.now().millisecondsSinceEpoch,
                    ),
                  ),
                IconButton(tooltip: 'Done', icon: const Icon(Icons.check), onPressed: () => store.markDone(it)),
                IconButton(
                  tooltip: 'Cancel',
                  icon: const Icon(Icons.close),
                  onPressed: () => store.updateRec(
                    'items', it, 'Cancelled: ${it['title']}', (r) => r['status'] = 'cancelled',
                  ),
                ),
              ],
            ),
            if (sug != null && sug.est != est)
              Row(
                children: [
                  Expanded(
                    child: Text('You usually take ${sug.ratio.toStringAsFixed(1)}x longer. Suggested: ${sug.est} min'),
                  ),
                  TextButton(
                    onPressed: () => store.updateRec(
                      'items', it, 'Estimate for ${it['title']}: ${sug.est} min', (r) => r['est'] = sug.est,
                    ),
                    child: const Text('Use'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
