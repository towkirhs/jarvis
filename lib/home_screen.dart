import 'package:flutter/material.dart';

import 'brain.dart';
import 'capture_page.dart';
import 'countdown_screen.dart';
import 'habits_screen.dart';
import 'items_screen.dart';
import 'money.dart';
import 'pages.dart';
import 'store.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});
  final Store store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _ctrl = TextEditingController();

  Store get s => widget.store;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    _ctrl.clear();
    await Brain.capture(s, t);
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: s, builder: (context, _) => _body(context));

  String? _overbooked(List<Rec> todays) {
    final minutes = todays
        .where((i) => i['kind'] == 'task')
        .fold<int>(0, (a, i) => a + ((i['est'] as int?) ?? 0));
    if (minutes > 480) {
      return 'Today has ${(minutes / 60).toStringAsFixed(1)} hours of tasks planned.';
    }
    final times = todays.where((i) => i['kind'] != 'task').map((i) => i['when'] as int).toList()..sort();
    for (var k = 1; k < times.length; k++) {
      if (times[k] - times[k - 1] < 30 * 60000) return 'Two events are less than 30 minutes apart.';
    }
    return null;
  }

  Widget _card(BuildContext context, String title, List<Widget> children, {Color? color}) => Card(
        color: color,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ...children,
            ],
          ),
        ),
      );

  Widget _body(BuildContext context) {
    final now = DateTime.now();
    final today = dayKey(now);
    final nowMs = now.millisecondsSinceEpoch;
    final scheme = Theme.of(context).colorScheme;
    final open = s.list('items').where((i) => i['status'] == 'open').toList();
    final behind = open.where((i) {
      final w = i['when'] as int?;
      return w != null && w < nowMs;
    }).toList();
    final todays = open.where((i) {
      final w = i['when'] as int?;
      return w != null && w >= nowMs && dayKey(fromMs(w)) == today;
    }).toList()
      ..sort((a, b) => (a['when'] as int).compareTo(b['when'] as int));
    final habits = s.habitsDueToday();
    final inbox = s.list('inbox').length;
    final recent = s.list('captures').reversed.take(8).toList();
    final warn = _overbooked(todays);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Today, $today', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Tell Jarvis anything. Dictate or type.',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Photo',
              icon: const Icon(Icons.add_a_photo_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CapturePage(store: s, startWithPhoto: true)),
              ),
            ),
            IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
          ],
        ),
        const SizedBox(height: 12),
        if (s.apiKey.isEmpty)
          _card(context, 'Turn on the AI', [
            const Text('Notes are saved, but nothing is understood until you add your Gemini key.'),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SettingsPage(store: s)),
                ),
                child: const Text('Open settings'),
              ),
            ),
          ], color: scheme.tertiaryContainer),
        if (inbox > 0)
          _card(context, '$inbox ${inbox == 1 ? 'item needs' : 'items need'} your review', [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => InboxPage(store: s)),
                ),
                child: const Text('Review'),
              ),
            ),
          ], color: scheme.secondaryContainer),
        if (warn != null) _card(context, 'Heads up', [Text(warn)], color: scheme.errorContainer),
        if (behind.isNotEmpty)
          _card(context, 'Behind schedule', [
            for (final i in behind) ItemTile(store: s, it: i, dense: true),
          ], color: scheme.errorContainer),
        if (habits.isNotEmpty)
          _card(context, 'Habits today', [
            for (final h in habits) HabitTodayRow(store: s, habit: h),
          ]),
        if (s.list('countdowns').any((c) => daysLeft(s, c) >= 0))
          _card(context, 'Countdowns', [
            for (final c in (s.list('countdowns').where((c) => daysLeft(s, c) >= 0).toList()
                  ..sort((a, b) => daysLeft(s, a).compareTo(daysLeft(s, b))))
                .take(3))
              Text('${c['title']}: ${daysText(daysLeft(s, c))}'),
          ]),
        if (s.list('tx').isNotEmpty)
          Builder(builder: (context) {
            num spentToday = 0;
            num spentMonth = 0;
            for (final t in s.list('tx').where((t) => t['type'] == 'expense')) {
              final d = fromMs(t['ts'] as int);
              if (d.year == now.year && d.month == now.month) spentMonth += t['amount'] as num;
              if (dayKey(d) == today) spentToday += t['amount'] as num;
            }
            return InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MoneyPage(store: s))),
              child: _card(context, 'Money', [
                Text('Spent today ${s.money(spentToday)}  ·  this month ${s.money(spentMonth)}'),
              ]),
            );
          }),
        _card(context, 'Coming up today', [
          if (todays.isEmpty) const Text('Nothing else planned for today.'),
          for (final i in todays) ItemTile(store: s, it: i, dense: true),
        ]),
        const SizedBox(height: 8),
        Text('Recent notes', style: Theme.of(context).textTheme.titleMedium),
        for (final c in recent) _capture(context, c),
      ],
    );
  }

  Widget _capture(BuildContext context, Rec c) {
    final status = c['status'] as String;
    final msg = (c['msg'] as String?) ?? '';
    final action = s.byId('actions', c['actionId'] as int?);
    final past = ((c['past'] as List?) ?? const []).map((e) => e.toString()).toList();
    final small = Theme.of(context).textTheme.bodySmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${clock(c['ts'] as int)}  ${c['cleaned']}'),
            if (status == 'pending') Text('Waiting to be processed...', style: small),
            if (msg.isNotEmpty) Text(msg, style: small),
            for (final p in past) Text(p, style: small?.copyWith(fontStyle: FontStyle.italic)),
            Row(
              children: [
                if (status == 'skipped' || status == 'failed')
                  TextButton(
                    onPressed: () {
                      c['status'] = 'pending';
                      s.save();
                      Brain.drain(s);
                    },
                    child: Text(status == 'skipped' ? 'Send anyway' : 'Retry'),
                  ),
                if (action != null && action['undone'] != true)
                  TextButton(onPressed: () => s.undo(action['id'] as int), child: const Text('Undo')),
                if (action != null && action['undone'] == true) Text('Undone', style: small),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
