import 'package:flutter/material.dart';

import 'clash.dart';
import 'habit_widgets.dart' show time12;
import 'haptics.dart';
import 'store.dart';

const countdownKinds = {
  'countdown': (Icons.hourglass_bottom, Colors.blue),
  'birthday': (Icons.cake_outlined, Colors.red),
  'anniversary': (Icons.favorite_border, Colors.pink),
  'holiday': (Icons.celebration_outlined, Colors.teal),
  'countup': (Icons.trending_up, Colors.orange),
};

/// Days from today to the countdown's (next) date; negative when it has passed.
int daysLeft(Store s, Rec c) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return s.countdownNext(c).difference(today).inDays;
}

String daysText(int d) => d == 0 ? 'Today' : (d > 0 ? '$d days left' : '${-d} days ago');

Future<void> _edit(BuildContext context, Store s, {String kind = 'countdown', Rec? c}) async {
  if (c != null) kind = c['kind'] as String? ?? 'countdown';
  final title = TextEditingController(text: c?['title'] as String? ?? '');
  var date = c == null ? DateTime.now() : DateTime.parse(c['date'] as String);
  final before = <int>{...((c?['before'] as List?)?.map((e) => (e as num).toInt()) ?? [0])};
  var time = c?['time'] as String? ?? CountdownAlert.defaultTime;
  var ring = c?['ring'] == true;
  final group = TextEditingController(text: c?['group'] as String? ?? '');
  final groups = countdownGroups(s);
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(c == null ? 'New $kind' : 'Edit'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text(dayKey(date)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setS(() => date = d);
                },
              ),
              TextField(
                controller: group,
                decoration: const InputDecoration(labelText: 'Group (optional)', hintText: 'Exams, Family birthdays…'),
              ),
              if (groups.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final g in groups)
                    ChoiceChip(
                      label: Text(g),
                      selected: group.text.trim() == g,
                      onSelected: (on) => setS(() => group.text = on ? g : ''),
                    ),
                ]),
              ],
              if (kind != 'countup') ...[
              const SizedBox(height: 16),
              const Text('Remind me'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final d in CountdownAlert.days)
                  FilterChip(
                    label: Text(CountdownAlert.name(d)),
                    selected: before.contains(d),
                    onSelected: (on) => setS(() => on ? before.add(d) : before.remove(d)),
                  ),
              ]),
              if (before.isNotEmpty) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.schedule),
                  label: Text('At ${time12(time)}'),
                  onPressed: () async {
                    final p = time.split(':');
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])),
                    );
                    if (t != null) setS(() => time = '${two(t.hour)}:${two(t.minute)}');
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ring as an alarm'),
                  subtitle: const Text('Otherwise a quiet notification'),
                  value: ring,
                  onChanged: (on) {
                    Haptics.toggle(on);
                    setS(() => ring = on);
                  },
                ),
              ],
              ],
            ],
          ),
        ),
        actions: [
          if (c != null)
            TextButton(
              onPressed: () {
                Haptics.warn();
                s.removeRec('countdowns', c, 'Deleted countdown ${c['title']}');
                Navigator.pop(ctx);
              },
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = title.text.trim();
              if (name.isEmpty) return;
              if (c == null) {
                final undo = <Rec>[];
                final rec = await s.addCountdown(name, dayKey(date), kind,
                    undo: undo, before: before.toList()..sort(), time: time, ring: ring);
                if (group.text.trim().isNotEmpty) rec['group'] = group.text.trim();
                s.logAction('Added countdown $name', undo);
                s.save();
              } else {
                await s.updateRec('countdowns', c, 'Edited countdown $name', (r) {
                  r['title'] = name;
                  r['date'] = dayKey(date);
                  r['before'] = before.toList()..sort();
                  r['time'] = time;
                  r['ring'] = ring;
                  if (group.text.trim().isEmpty) {
                    r.remove('group');
                  } else {
                    r['group'] = group.text.trim();
                  }
                });
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

class CountdownPage extends StatelessWidget {
  const CountdownPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Countdowns')),
        floatingActionButton: PopupMenuButton<String>(
          onSelected: (k) => _edit(context, store, kind: k),
          itemBuilder: (_) => [
            for (final e in countdownKinds.entries)
              PopupMenuItem(
                value: e.key,
                child: Row(children: [
                  Icon(e.value.$1, color: e.value.$2),
                  const SizedBox(width: 8),
                  Text(e.key[0].toUpperCase() + e.key.substring(1)),
                ]),
              ),
          ],
          child: const FloatingActionButton(onPressed: null, child: Icon(Icons.add)),
        ),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final all = store.list('countdowns').toList()
              ..sort((a, b) => daysLeft(store, a).abs().compareTo(daysLeft(store, b).abs()));
            if (all.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No countdowns. Tap +, or tell Jarvis "my exam is on 20 December".'),
                ),
              );
            }
            final grouped = <String, List<Rec>>{};
            for (final c in all) {
              final g = c['group'] as String?;
              if (g != null) (grouped[g] ??= []).add(c);
            }
            final loose = all.where((c) => c['group'] == null);
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final g in countdownGroups(store))
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      initiallyExpanded: true,
                      shape: const Border(),
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(g, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${grouped[g]!.length} saved  ·  nearest: ${grouped[g]!.first['title']}'),
                      children: [for (final c in grouped[g]!) _tile(context, store, c, flat: true)],
                    ),
                  ),
                for (final c in loose) _tile(context, store, c),
              ],
            );
          },
        ),
      );
}

/// Group names in use, A to Z.
List<String> countdownGroups(Store s) =>
    {for (final c in s.list('countdowns')) if (c['group'] is String) c['group'] as String}.toList()..sort();

Widget _tile(BuildContext context, Store store, Rec c, {bool flat = false}) {
  final kind = countdownKinds[c['kind']] ?? countdownKinds['countdown']!;
  final d = daysLeft(store, c);
  final primary = Theme.of(context).colorScheme.primary;
  Widget figure(String big, String small) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(big, style: TextStyle(fontSize: 22, color: primary)),
          Text(small, style: const TextStyle(fontSize: 11)),
        ],
      );
  final tile = ListTile(
    onTap: () => _edit(context, store, c: c),
    leading: CircleAvatar(
      backgroundColor: kind.$2.withValues(alpha: 0.2),
      child: Icon(kind.$1, color: kind.$2),
    ),
    title: Text(c['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text('${c['date']}${c['yearly'] == true ? '  ·  every year' : ''}'),
    trailing: c['kind'] == 'countup'
        ? figure('${d.abs()}', d <= 0 ? 'days so far' : 'days to start')
        : d == 0
            ? Text('Today', style: TextStyle(fontSize: 20, color: primary))
            : figure('${d.abs()}', d > 0 ? 'days left' : 'days ago'),
  );
  return flat ? tile : Card(child: tile);
}
