import 'package:flutter/material.dart';

import 'store.dart';
import 'task_sheet.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
  'October', 'November', 'December'];

int _byWhen(Rec a, Rec b) {
  final x = a['when'] as int?;
  final y = b['when'] as int?;
  if (x == null && y == null) return 0;
  if (x == null) return 1;
  if (y == null) return -1;
  return x.compareTo(y);
}

/// The Plan tab: List, Calendar and Eisenhower Matrix views of the same items.
class ItemsScreen extends StatelessWidget {
  const ItemsScreen({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          floatingActionButton: FloatingActionButton(
            onPressed: () => showTaskSheet(context, store),
            child: const Icon(Icons.add),
          ),
          body: Column(
            children: [
              const TabBar(tabs: [Tab(text: 'List'), Tab(text: 'Calendar'), Tab(text: 'Matrix')]),
              Expanded(
                child: TabBarView(
                  children: [
                    _ListView(store: store),
                    _CalendarView(store: store),
                    _MatrixView(store: store),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// One item row: tap to edit, buttons to start, finish or cancel.
class ItemTile extends StatelessWidget {
  const ItemTile({super.key, required this.store, required this.it, this.dense = false});
  final Store store;
  final Rec it;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final w = it['when'] as int?;
    final est = it['est'] as int?;
    final postponed = (it['postponed'] as int?) ?? 0;
    final started = it['startedAt'] != null;
    final open = it['status'] == 'open';
    final priority = (it['priority'] as int?) ?? 0;
    final tags = ((it['tags'] as List?) ?? []).cast<String>();
    final sug = open ? store.estimateSuggestion(it['cat'] as String?, est) : null;
    final icon = it['kind'] == 'task'
        ? (open ? Icons.check_box_outline_blank : Icons.check_box)
        : (it['kind'] == 'alarm' ? Icons.alarm : Icons.event);
    final details = [
      if (w != null) niceWhen(w),
      if (it['repeat'] != null) repeatNames[it['repeat']]!,
      if (est != null) '$est min',
      if (it['dur'] != null) '${it['dur']} min',
      if (postponed > 0) 'postponed ${postponed}x',
      if (started) 'started',
      if ((it['list'] ?? 'Inbox') != 'Inbox') '${it['list']}',
    ].join('  ·  ');
    return Card(
      child: InkWell(
        onTap: () => showTaskSheet(context, store, item: it),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(icon, color: priority > 0 ? priorityColors[priority] : null),
                    tooltip: open ? 'Done' : null,
                    onPressed: open ? () => store.markDone(it) : null,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          it['title'] as String,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            decoration: open ? null : TextDecoration.lineThrough,
                          ),
                        ),
                        if (details.isNotEmpty) Text(details, style: Theme.of(context).textTheme.bodySmall),
                        if (tags.isNotEmpty)
                          Text(tags.map((t) => '#$t').join(' '),
                              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (open && it['kind'] == 'task' && !started && !dense)
                    IconButton(
                      tooltip: 'Start',
                      icon: const Icon(Icons.play_arrow),
                      onPressed: () => store.updateRec(
                        'items', it, 'Started: ${it['title']}',
                        (r) => r['startedAt'] = DateTime.now().millisecondsSinceEpoch,
                      ),
                    ),
                  if (open && !dense)
                    IconButton(
                      tooltip: 'Cancel',
                      icon: const Icon(Icons.close),
                      onPressed: () => store.updateRec(
                        'items', it, 'Cancelled: ${it['title']}', (r) => r['status'] = 'cancelled',
                      ),
                    ),
                ],
              ),
              if (sug != null && sug.est != est && !dense)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
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
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListView extends StatefulWidget {
  const _ListView({required this.store});
  final Store store;

  @override
  State<_ListView> createState() => _ListViewState();
}

class _ListViewState extends State<_ListView> {
  String _filter = 'All';

  bool _matches(Rec it) {
    final w = it['when'] as int?;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_filter) {
      case 'All':
        return true;
      case 'Today':
        return w != null && fromMs(w).isBefore(DateTime(today.year, today.month, today.day + 1));
      case 'Next 7 days':
        return w != null && fromMs(w).isBefore(DateTime(today.year, today.month, today.day + 7));
    }
    if (_filter.startsWith('#')) return ((it['tags'] as List?) ?? []).contains(_filter.substring(1));
    return ((it['list'] as String?) ?? 'Inbox') == _filter;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final s = widget.store;
          final tags = {for (final i in s.list('items')) ...((i['tags'] as List?) ?? []).cast<String>()};
          final filters = ['All', 'Today', 'Next 7 days', ...allLists(s), for (final t in tags) '#$t'];
          if (!filters.contains(_filter)) _filter = 'All';
          final open = s.list('items').where((i) => i['status'] == 'open' && _matches(i)).toList()..sort(_byWhen);
          final done = s.list('items').where((i) => i['status'] == 'done' && _matches(i)).toList().reversed.take(10).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
            children: [
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final f in filters)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(f),
                          selected: f == _filter,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (open.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing here. Tap + or tell Jarvis.')),
              for (final it in open) ItemTile(store: s, it: it),
              if (done.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Recently done', style: Theme.of(context).textTheme.titleMedium),
                for (final it in done) ItemTile(store: s, it: it, dense: true),
              ],
            ],
          );
        },
      );
}

class _CalendarView extends StatefulWidget {
  const _CalendarView({required this.store});
  final Store store;

  @override
  State<_CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<_CalendarView> {
  DateTime _day = DateTime.now();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final s = widget.store;
          final monday = s.mondayOf(_day);
          final week = [for (var i = 0; i < 7; i++) DateTime(monday.year, monday.month, monday.day + i)];
          final key = dayKey(_day);
          final todayKey = dayKey(DateTime.now());
          final items = s.list('items').where((i) {
            final w = i['when'] as int?;
            return w != null && i['status'] != 'cancelled' && dayKey(fromMs(w)) == key;
          }).toList()
            ..sort(_byWhen);
          final countdowns = s.list('countdowns').where((c) => dayKey(s.countdownNext(c)) == key).toList();
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
            children: [
              Row(
                children: [
                  Text('${_months[_day.month - 1]} ${_day.year}', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() => _day = DateTime(_day.year, _day.month, _day.day - 7)),
                  ),
                  TextButton(onPressed: () => setState(() => _day = DateTime.now()), child: const Text('Today')),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setState(() => _day = DateTime(_day.year, _day.month, _day.day + 7)),
                  ),
                ],
              ),
              Row(
                children: [
                  for (final d in week)
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _day = d),
                        borderRadius: BorderRadius.circular(24),
                        child: Column(
                          children: [
                            Text(_weekdays[d.weekday - 1], style: Theme.of(context).textTheme.labelSmall),
                            const SizedBox(height: 4),
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: dayKey(d) == key ? scheme.primary : Colors.transparent,
                              child: Text(
                                '${d.day}',
                                style: TextStyle(
                                  color: dayKey(d) == key
                                      ? scheme.onPrimary
                                      : (dayKey(d) == todayKey ? scheme.primary : null),
                                  fontWeight: dayKey(d) == todayKey ? FontWeight.bold : null,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            // A dot when the day has something on it.
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: s.list('items').any((i) {
                                  final w = i['when'] as int?;
                                  return w != null && i['status'] == 'open' && dayKey(fromMs(w)) == dayKey(d);
                                })
                                    ? scheme.primary
                                    : Colors.transparent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (countdowns.isNotEmpty)
                Card(
                  child: Column(
                    children: [
                      for (final c in countdowns)
                        ListTile(leading: const Icon(Icons.hourglass_bottom), title: Text(c['title'] as String)),
                    ],
                  ),
                ),
              if (items.isEmpty && countdowns.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text('Nothing on this day.')),
              for (final it in items) ItemTile(store: s, it: it, dense: true),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text('Add on $key'),
                  onPressed: () => showTaskSheet(context, s, day: _day),
                ),
              ),
            ],
          );
        },
      );
}

/// Eisenhower Matrix. Priority decides the quadrant: High = urgent and important,
/// Medium = important, Low = urgent, None = neither. Moving a task changes its priority.
class _MatrixView extends StatelessWidget {
  const _MatrixView({required this.store});
  final Store store;

  static const _quadrants = [
    (3, 'Urgent & Important', Colors.red),
    (2, 'Not Urgent & Important', Colors.orange),
    (1, 'Urgent & Unimportant', Colors.blue),
    (0, 'Not Urgent & Unimportant', Colors.teal),
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final open = store.list('items').where((i) => i['status'] == 'open').toList()..sort(_byWhen);
          Widget quadrant((int, String, MaterialColor) q) {
            final (p, name, color) = q;
            final items = open.where((i) => ((i['priority'] as int?) ?? 0) == p).toList();
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Expanded(
                      child: items.isEmpty
                          ? const Center(child: Text('No tasks'))
                          : ListView(
                              children: [
                                for (final it in items)
                                  InkWell(
                                    onTap: () => showTaskSheet(context, store, item: it),
                                    onLongPress: () => _move(context, it),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          InkWell(
                                            onTap: () => store.markDone(it),
                                            child: const Icon(Icons.check_box_outline_blank, size: 20),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(it['title'] as String),
                                                if (it['when'] != null)
                                                  Text(niceWhen(it['when'] as int),
                                                      style: TextStyle(fontSize: 11, color: color)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
            child: Column(
              children: [
                const Text('Long-press a task to move it to another box.'),
                Expanded(
                  child: Row(children: [Expanded(child: quadrant(_quadrants[0])), Expanded(child: quadrant(_quadrants[1]))]),
                ),
                Expanded(
                  child: Row(children: [Expanded(child: quadrant(_quadrants[2])), Expanded(child: quadrant(_quadrants[3]))]),
                ),
              ],
            ),
          );
        },
      );

  Future<void> _move(BuildContext context, Rec it) async {
    final p = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Move "${it['title']}"'),
        children: [
          for (final (p, name, color) in _quadrants)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p),
              child: Text(name, style: TextStyle(color: color)),
            ),
        ],
      ),
    );
    if (p == null) return;
    await store.updateRec('items', it, 'Moved ${it['title']} to ${priorityNames[p]} priority', (r) => r['priority'] = p);
  }
}
