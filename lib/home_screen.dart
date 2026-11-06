import 'package:flutter/material.dart';

import 'brain.dart';
import 'capture_page.dart';
import 'countdown_screen.dart';
import 'habits_screen.dart';
import 'haptics.dart';
import 'items_screen.dart';
import 'money.dart';
import 'plan_day_page.dart';
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
    Haptics.tap();
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

  /// A titled group. Colour is kept for the title icon only, so warnings stand out without shouting.
  Widget _section(BuildContext context, String title, List<Widget> children,
      {IconData? icon, Color? iconColor, Widget? trailing}) {
    final tt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 32,
              child: Row(
                children: [
                  if (icon != null) ...[Icon(icon, size: 18, color: iconColor), const SizedBox(width: 8)],
                  Expanded(child: Text(title, style: tt.titleSmall)),
                  if (trailing != null) trailing,
                ],
              ),
            ),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      ),
    );
  }

  /// A one-line notice that leads somewhere.
  Widget _banner(BuildContext context, IconData icon, String text, Color color, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: Color.alphaBlend(color.withValues(alpha: 0.12), scheme.surfaceContainerLow),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  /// A big number with a small label: the things you glance at.
  Widget _stat(BuildContext context, String value, String label, IconData icon, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(height: 10),
                Text(value, style: tt.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(label, style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  Widget _body(BuildContext context) {
    final now = DateTime.now();
    final today = dayKey(now);
    final nowMs = now.millisecondsSinceEpoch;
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final open = s.list('items').where((i) => i['status'] == 'open').toList();
    final behind = open.where((i) {
      final w = i['when'] as int?;
      // An all-day item is only behind once its day is over.
      return w != null && w < nowMs && !(i['allDay'] == true && dayKey(fromMs(w)) == today);
    }).toList();
    final todays = open.where((i) {
      final w = i['when'] as int?;
      return w != null && (w >= nowMs || i['allDay'] == true) && dayKey(fromMs(w)) == today;
    }).toList()
      ..sort((a, b) => (a['when'] as int).compareTo(b['when'] as int));
    final habits = s.habitsDueToday();
    final inbox = s.list('inbox').length;
    final recent = s.list('captures').reversed.take(8).toList();
    final warn = _overbooked(todays);
    final countdowns = s.list('countdowns').where((c) => daysLeft(s, c) >= 0).toList()
      ..sort((a, b) => daysLeft(s, a).compareTo(daysLeft(s, b)));
    num spentToday = 0;
    for (final t in s.list('tx').where((t) => t['type'] == 'expense')) {
      if (dayKey(fromMs(t['ts'] as int)) == today) spentToday += t['amount'] as num;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        Text(
          now.hour < 12 ? 'Good morning' : (now.hour < 17 ? 'Good afternoon' : 'Good evening'),
          style: tt.headlineMedium,
        ),
        const SizedBox(height: 2),
        Text(
          '${const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][now.weekday - 1]}, '
          '${now.day} ${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][now.month - 1]}'
          '${todays.isEmpty ? '' : '  ·  ${todays.length} left today'}',
          style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        // The one thing every visit is for: telling Jarvis something.
        Container(
          padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
          decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(26)),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Tell Jarvis anything',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Photo',
                icon: Icon(Icons.add_a_photo_outlined, color: scheme.onSurfaceVariant),
                onPressed: () => _open(context, CapturePage(store: s, startWithPhoto: true)),
              ),
              IconButton.filled(tooltip: 'Send', onPressed: _send, icon: const Icon(Icons.arrow_upward)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (s.apiKey.isEmpty)
          _banner(context, Icons.key_outlined, 'Add your Gemini key to turn on the AI', scheme.tertiary,
              () => _open(context, SettingsPage(store: s))),
        if (inbox > 0)
          _banner(context, Icons.inbox_outlined, '$inbox ${inbox == 1 ? 'note needs' : 'notes need'} your review',
              scheme.primary, () => _open(context, InboxPage(store: s))),
        if (warn != null)
          _banner(context, Icons.warning_amber_rounded, warn, scheme.error,
              () => _open(context, PlanDayPage(store: s))),
        if (behind.isNotEmpty)
          _section(context, 'Behind schedule', [
            for (final i in behind) ItemTile(store: s, it: i, dense: true),
          ], icon: Icons.error_outline, iconColor: scheme.error),
        LabelCard(store: s),
        if (countdowns.isNotEmpty || s.list('tx').isNotEmpty)
          Row(
            children: [
              if (s.list('tx').isNotEmpty)
                _stat(context, s.money(spentToday), 'spent today', Icons.account_balance_wallet_outlined,
                    () => _open(context, MoneyPage(store: s))),
              if (countdowns.isNotEmpty && s.list('tx').isNotEmpty) const SizedBox(width: 10),
              if (countdowns.isNotEmpty)
                _stat(
                  context,
                  daysLeft(s, countdowns.first) == 0 ? 'Today' : '${daysLeft(s, countdowns.first)} days',
                  'until ${countdowns.first['title']}',
                  Icons.hourglass_bottom,
                  () => _open(context, CountdownPage(store: s)),
                ),
            ],
          ),
        _section(
          context,
          'Coming up today',
          [
            if (todays.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('Nothing else planned for today.', style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            for (final i in todays) ItemTile(store: s, it: i, dense: true),
          ],
          icon: Icons.today_outlined,
          iconColor: scheme.primary,
          trailing: TextButton.icon(
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('Plan my day'),
            onPressed: () => _open(context, PlanDayPage(store: s)),
          ),
        ),
        if (habits.isNotEmpty)
          _section(context, 'Habits today', [
            for (final h in habits) HabitTodayRow(store: s, habit: h, flat: true),
          ], icon: Icons.local_fire_department_outlined, iconColor: scheme.primary),
        if (recent.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
            child: Text('Recent notes', style: tt.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          Card(
            child: Column(
              children: [
                for (var k = 0; k < recent.length; k++) ...[
                  if (k > 0) const Divider(indent: 16, endIndent: 16),
                  _capture(context, recent[k]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _capture(BuildContext context, Rec c) {
    final status = c['status'] as String;
    final msg = (c['msg'] as String?) ?? '';
    final action = s.byId('actions', c['actionId'] as int?);
    final past = ((c['past'] as List?) ?? const []).map((e) => e.toString()).toList();
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(clock(c['ts'] as int), style: small),
            const SizedBox(height: 2),
            Text('${c['cleaned']}', style: Theme.of(context).textTheme.bodyLarge),
            if (status == 'pending') Text('Waiting to be processed...', style: small),
            if (msg.isNotEmpty) Text(msg, style: small),
            if (c['via'] == 'phone') Text('Understood on this phone, no AI used', style: small?.copyWith(fontStyle: FontStyle.italic)),
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
                  TextButton(
                    onPressed: () {
                      Haptics.tick();
                      s.undo(action['id'] as int);
                    },
                    child: const Text('Undo'),
                  ),
                if (action != null && action['undone'] == true) Text('Undone', style: small),
              ],
            ),
          ],
        ),
      );
  }
}
