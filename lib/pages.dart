import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'haptics.dart';
import 'brain.dart';
import 'countdown_screen.dart';
import 'focus_screen.dart';
import 'habit_core.dart';
import 'habits_screen.dart';
import 'native.dart';
import 'decide_page.dart';
import 'rent_page.dart';
import 'store.dart';
import 'sync.dart';
import 'sync_page.dart';
import 'theme.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          void open(Widget page) =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => page));
          final inbox = store.list('inbox').length;
          final promises = store.list('promises').where((p) => p['status'] == 'open').length;
          Widget tile(IconData icon, String title, String? sub, Widget page, {int badge = 0}) => ListTile(
                leading: Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: Icon(icon)),
                title: Text(title),
                subtitle: sub == null ? null : Text(sub),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(page),
              );
          Widget group(String name, List<Widget> tiles) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
                    child: Text(name, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
                  ),
                  Card(child: Column(children: tiles)),
                ],
              );
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
            children: [
              Text('More', style: Theme.of(context).textTheme.headlineSmall),
              group('Plan', [
                tile(Icons.inbox_outlined, 'Review inbox', inbox == 0 ? 'All clear' : '$inbox waiting', InboxPage(store: store), badge: inbox),
                tile(Icons.handshake_outlined, 'Promises', '$promises open', PromisesPage(store: store)),
                tile(Icons.hourglass_bottom, 'Countdowns', '${store.list('countdowns').length} saved', CountdownPage(store: store)),
                tile(Icons.meeting_room_outlined, 'Rooms and rent', '${store.list('rooms').length} rooms', RentPage(store: store)),
                tile(Icons.balance, 'Decide', 'Odds, not chat', DecidePage(store: store)),
                tile(Icons.history_edu_outlined, 'Decisions', null, DecisionsPage(store: store)),
              ]),
              group('Tools', [
                tile(
                  Icons.timer_outlined,
                  'Focus',
                  store.focusActive == null ? 'Pomodoro and stopwatch' : 'Running now',
                  Scaffold(appBar: AppBar(title: const Text('Focus')), body: FocusScreen(store: store)),
                ),
                tile(Icons.insights, 'Insights', null, InsightsPage(store: store)),
              ]),
              group('App', [
                tile(Icons.undo, 'Activity and undo', null, ActivityPage(store: store)),
                tile(Icons.settings_outlined, 'Settings', null, SettingsPage(store: store)),
              ]),
            ],
          );
        },
      );
}

// ---------------------------------------------------------------- inbox

class InboxPage extends StatelessWidget {
  const InboxPage({super.key, required this.store});
  final Store store;

  Future<DateTime?> _pickWhen(BuildContext context) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (d == null || !context.mounted) return null;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _accept(BuildContext context, Rec e) async {
    final p = e['item'] as Map;
    final type = p['type'];
    String? date;
    String? time;
    String? target;
    String? habit;

    final needsTime = (type == 'alarm' || type == 'event') && p['time'] == null;
    final needsNewTime = type == 'delay' && p['time'] == null && p['date'] == null;
    if (needsTime || needsNewTime) {
      final d = await _pickWhen(context);
      if (d == null) return;
      date = dayKey(d);
      time = '${two(d.hour)}:${two(d.minute)}';
    }
    if (type == 'delay' && Brain.findItem(store, p['target'] as String?) == null) {
      if (!context.mounted) return;
      final open = store.list('items').where((i) => i['status'] == 'open').toList();
      final chosen = await showDialog<Rec>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Which item?'),
          children: [
            for (final i in open)
              SimpleDialogOption(onPressed: () => Navigator.pop(ctx, i), child: Text(i['title'] as String)),
          ],
        ),
      );
      if (chosen == null) return;
      target = chosen['title'] as String;
    }
    if (type == 'habit_new') {
      // Let the person fill in or fix the details, then the review item is done.
      final h = await showAddHabit(context, store, name: (p['habit'] as String?) ?? '');
      if (h == null) return;
      store.list('inbox').removeWhere((r) => r['id'] == e['id']);
      store.save();
      return;
    }
    if (type == 'habit_log' && Brain.findHabit(store, p['habit'] as String?) == null) {
      if (!context.mounted) return;
      final h = await showAddHabit(context, store, name: (p['habit'] as String?) ?? '');
      if (h == null) return;
      habit = h['name'] as String;
    }
    if (type == 'countdown' && p['date'] == null) {
      if (!context.mounted) return;
      final now = DateTime.now();
      final d = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
      );
      if (d == null) return;
      date = dayKey(d);
    }
    if (type == 'promise' && p['date'] == null) {
      if (!context.mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Deadline for this promise?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'none'), child: const Text('No date')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'pick'), child: const Text('Pick a date')),
          ],
        ),
      );
      if (choice == null) return;
      if (choice == 'pick') {
        if (!context.mounted) return;
        final now = DateTime.now();
        final d = await showDatePicker(
          context: context,
          initialDate: now.add(const Duration(days: 1)),
          firstDate: now,
          lastDate: now.add(const Duration(days: 730)),
        );
        if (d == null) return;
        date = dayKey(d);
      }
    }
    await Brain.acceptInbox(store, e, date: date, time: time, target: target, habit: habit);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Review inbox')),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final items = store.list('inbox');
            if (items.isEmpty) return const Center(child: Text('Nothing to review.'));
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final e in items)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${(e['item'] as Map)['title'] ?? (e['item'] as Map)['type']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text('${(e['item'] as Map)['type']}  ·  ${e['why']}'),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Brain.discardInbox(store, e),
                                child: const Text('Discard'),
                              ),
                              FilledButton(onPressed: () => _accept(context, e), child: const Text('Accept')),
                            ],
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

// ---------------------------------------------------------------- activity

class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Activity and undo')),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final actions = store.list('actions').reversed.toList();
            if (actions.isEmpty) return const Center(child: Text('Nothing yet.'));
            return ListView(
              children: [
                for (final a in actions)
                  ListTile(
                    title: Text(a['desc'] as String, maxLines: 3, overflow: TextOverflow.ellipsis),
                    subtitle: Text(niceWhen(a['ts'] as int)),
                    trailing: a['undone'] == true
                        ? const Text('Undone')
                        : TextButton(
                            onPressed: () {
                              Haptics.tick();
                              store.undo(a['id'] as int);
                            },
                            child: const Text('Undo'),
                          ),
                  ),
              ],
            );
          },
        ),
      );
}

// ---------------------------------------------------------------- promises

class PromisesPage extends StatelessWidget {
  const PromisesPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Promises')),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final open = store.list('promises').where((p) => p['status'] == 'open').toList();
            final done = store.list('promises').where((p) => p['status'] == 'done').toList().reversed.take(10).toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('You owe', style: Theme.of(context).textTheme.titleMedium),
                if (open.isEmpty) const Text('No open promises.'),
                for (final p in open)
                  Card(
                    child: ListTile(
                      title: Text('${p['person']}: ${p['what']}'),
                      subtitle: Text(p['due'] == null ? 'No deadline' : 'By ${niceWhen(p['due'] as int)}'),
                      trailing: IconButton(
                        tooltip: 'Kept',
                        icon: const Icon(Icons.check),
                        onPressed: () => store.updateRec(
                          'promises', p, 'Kept promise to ${p['person']}', (r) => r['status'] = 'done',
                        ),
                      ),
                    ),
                  ),
                if (done.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Kept', style: Theme.of(context).textTheme.titleMedium),
                  for (final p in done)
                    ListTile(dense: true, title: Text('${p['person']}: ${p['what']}')),
                ],
              ],
            );
          },
        ),
      );
}

// ---------------------------------------------------------------- decisions

class DecisionsPage extends StatelessWidget {
  const DecisionsPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Decisions')),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final all = store.list('decisions').reversed.toList();
            if (all.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No decisions yet. Say things like: I decided not to take the job because of the commute.'),
                ),
              );
            }
            return ListView(
              children: [
                for (final d in all)
                  ListTile(
                    title: Text(d['decision'] as String),
                    subtitle: Text(
                      '${dayKey(fromMs(d['ts'] as int))}${d['reason'] == null ? '' : '\nBecause ${d['reason']}'}',
                    ),
                    isThreeLine: d['reason'] != null,
                  ),
              ],
            );
          },
        ),
      );
}

// ---------------------------------------------------------------- insights

class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Insights')),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final postponed = store.list('items').where((i) => ((i['postponed'] as int?) ?? 0) > 0).toList()
              ..sort((a, b) => (b['postponed'] as int).compareTo(a['postponed'] as int));
            final byCat = <String, List<double>>{};
            for (final i in store.list('items')) {
              final a = i['actual'] as int?;
              final e = i['est'] as int?;
              final c = i['cat'] as String?;
              if (i['status'] == 'done' && a != null && e != null && e > 0 && c != null) {
                byCat.putIfAbsent(c, () => <double>[]).add(a / e);
              }
            }
            final weekAgo = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
            final notes = store.list('captures').where((c) => (c['ts'] as int) >= weekAgo).length;
            final style = Theme.of(context).textTheme.titleMedium;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Last 7 days: $notes notes, '
                    '${store.list('items').where((i) => i['status'] == 'done' && ((i['doneAt'] as int?) ?? 0) >= weekAgo).length} tasks done',
                    style: style),
                const SizedBox(height: 16),
                Text('Postponed most', style: style),
                if (postponed.isEmpty) const Text('Nothing postponed.'),
                for (final i in postponed.take(5)) Text('${i['title']}: ${i['postponed']}x'),
                const SizedBox(height: 16),
                Text('Habits this week', style: style),
                if (store.list('habits').isEmpty) const Text('No habits yet.'),
                for (final h in store.list('habits'))
                  Text(
                    '${h['name']}: ${HabitCore.describe(h).toLowerCase()}, '
                    '${HabitCore.consistency(h, DateTime.now())}% consistent, streak ${store.streakPeriods(h)} ${HabitCore.unit(h)}s',
                  ),
                const SizedBox(height: 16),
                Text('How long things really take', style: style),
                if (byCat.isEmpty) const Text('Start and finish tasks with an estimate to see this.'),
                for (final e in byCat.entries)
                  Text(
                    '${e.key}: ${e.value.length} tasks, about '
                    '${(e.value.reduce((a, b) => a + b) / e.value.length).toStringAsFixed(1)}x your estimate',
                  ),
              ],
            );
          },
        ),
      );
}

// ---------------------------------------------------------------- settings

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store});
  final Store store;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _key = TextEditingController(text: widget.store.apiKey);
  late final TextEditingController _model =
      TextEditingController(text: (widget.store.settings['model'] as String?) ?? '');

  Store get s => widget.store;

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  void _say(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _saveAi() async {
    await s.setApiKey(_key.text);
    s.settings['model'] = _model.text.trim().isEmpty ? 'gemini-2.5-flash-lite' : _model.text.trim();
    s.save();
    _say('Saved.');
    await Brain.drain(s);
  }

  Future<void> _restore() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup'),
        content: TextField(
          controller: ctrl,
          maxLines: 6,
          decoration: const InputDecoration(hintText: 'Paste the backup text. This replaces everything here.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await s.importBackup(ctrl.text.trim());
      _say('Backup restored.');
    } catch (e) {
      _say('That did not look like a Jarvis backup.');
    }
  }

  Future<void> _showLog() async {
    final log = await Native.getLog();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alarm log'),
        content: SingleChildScrollView(
          child: Text(log.isEmpty ? 'Empty' : log, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('AI', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _key,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Gemini API key',
                helperText: 'Stored only on this device. Not part of backups.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _model,
              decoration: const InputDecoration(
                labelText: 'Model',
                helperText: 'Change this if Google retires the default.',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _saveAi, child: const Text('Save')),
            ),
            const Divider(height: 32),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Currency sign'),
              trailing: SizedBox(
                width: 60,
                child: TextFormField(
                  initialValue: s.currency,
                  textAlign: TextAlign.center,
                  onChanged: (v) {
                    s.settings['currency'] = v.trim();
                    s.save();
                  },
                ),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Theme'),
              trailing: DropdownButton<String>(
                value: (s.settings['theme'] as String?) ?? 'system',
                items: [for (final e in themeNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) {
                  if (v == null) return;
                  s.settings['theme'] = v;
                  s.save();
                  setState(() {});
                },
              ),
            ),
            const Text('Colour'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final e in accents.entries)
                  Builder(builder: (context) {
                    final picked = ((s.settings['accent'] as String?) ?? 'default') == e.key;
                    return Semantics(
                      label: e.key,
                      selected: picked,
                      child: InkResponse(
                        onTap: () {
                          Haptics.tick();
                          s.settings['accent'] = e.key;
                          s.save();
                          setState(() {});
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: e.value,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: picked ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: picked ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                        ),
                      ),
                    );
                  }),
              ],
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final recent = s.list('captures').where((c) => c['via'] != null).toList().reversed.take(100).toList();
              final onPhone = recent.where((c) => c['via'] == 'phone').length;
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Understand simple notes on the phone'),
                subtitle: Text(
                  'Alarms, timed tasks, money, habits and birthdays are read without an AI call: faster, offline, '
                  'and saves your Gemini quota.${recent.isEmpty ? '' : ' Recently $onPhone of ${recent.length} notes needed no AI.'}',
                ),
                value: s.settings['local'] != false,
                onChanged: (v) {
                  s.settings['local'] = v;
                  s.save();
                  setState(() {});
                },
              );
            }),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Keep small talk on this phone'),
              subtitle: const Text('Notes that do not look like plans, tasks or reflections are never sent to the AI.'),
              value: s.settings['prefilter'] == true,
              onChanged: (v) {
                s.settings['prefilter'] = v;
                s.save();
                setState(() {});
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Act on its own when at least'),
              subtitle: const Text('Below this, notes go to your review inbox and decisions are left to you.'),
              trailing: Text('${(s.sureEnough * 100).round()}% sure', style: Theme.of(context).textTheme.titleSmall),
            ),
            Slider(
              value: s.sureEnough,
              min: 0.5,
              max: 0.95,
              divisions: 9,
              label: '${(s.sureEnough * 100).round()}%',
              onChanged: (v) {
                s.settings['sure'] = v;
                s.save();
                setState(() {});
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vibrate on actions'),
              subtitle: const Text('A light tap when you send, finish a task, or delete something.'),
              value: s.settings['haptics'] != false,
              onChanged: (v) {
                s.settings['haptics'] = v;
                s.save();
                if (v) Haptics.success();
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Daily reminder limit'),
              subtitle: const Text('Alarms you ask for are never limited.'),
              trailing: DropdownButton<int>(
                value: s.cap,
                items: [for (var n = 3; n <= 12; n++) DropdownMenuItem(value: n, child: Text('$n'))],
                onChanged: (v) {
                  if (v == null) return;
                  s.settings['cap'] = v;
                  s.save();
                  s.resyncAll();
                  setState(() {});
                },
              ),
            ),
            const Divider(height: 32),
            Text('Backup and other devices', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_sync_outlined),
                title: const Text('Encrypted sync'),
                subtitle: Text(Sync.enabled(s) ? 'On' : 'Off — set up to never lose anything'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SyncPage(store: s)));
                  if (mounted) setState(() {});
                },
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: s.exportBackup()));
                    _say('Backup copied. Paste it somewhere safe.');
                  },
                  child: const Text('Copy backup'),
                ),
                OutlinedButton(onPressed: _restore, child: const Text('Restore backup')),
              ],
            ),
            const Divider(height: 32),
            Text('Alarms', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    await Native.schedule(
                      id: s.nextId(),
                      millis: DateTime.now().millisecondsSinceEpoch + 60000,
                      kind: 'alarm',
                      label: 'Test alarm',
                    );
                    _say('A test alarm will ring in 1 minute.');
                  },
                  child: const Text('Test alarm in 1 minute'),
                ),
                OutlinedButton(onPressed: _showLog, child: const Text('Alarm log')),
              ],
            ),
          ],
        ),
      );
}
