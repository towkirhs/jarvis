import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'native.dart';
import 'ai.dart';

import 'shapes.dart';
import 'brain.dart';
import 'capture_page.dart';
import 'countdown_screen.dart';
import 'day_ribbon.dart';
import 'decide.dart';
import 'decide_page.dart';
import 'habits_screen.dart';
import 'haptics.dart';
import 'items_screen.dart';
import 'money.dart';
import 'plan_day_page.dart';
import 'pages.dart';
import 'store.dart';
import 'task_sheet.dart';

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
    // Phone actions ("open YouTube", "message Oishi on WhatsApp") run right away; the rest goes to Jarvis.
    final did = await Native.command(t);
    if (did != null) {
      logCommand(s, t, did);
      return;
    }
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
                  if (icon != null) ...[ShapeIcon(icon, color: iconColor, size: 32), const SizedBox(width: 12)],
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
                const SizedBox(height: 12),
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

  /// Everything about today: what was the old Home, now a panel you pull up from the chat.
  List<Widget> _today(BuildContext context) {
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
    final countdowns = s.list('countdowns').where((c) => daysLeft(s, c) >= 0).toList()
      ..sort((a, b) => daysLeft(s, a).compareTo(daysLeft(s, b)));
    final now0 = Decide.whatNow(s.list('items'), now);
    final nowPick = now0.pick == 'nothing' ? null : s.byId('items', int.parse(now0.pick));
    final spentToday = _spentToday();
    return [
      if (behind.isNotEmpty)
        _section(context, 'Behind schedule', [
          for (final i in behind) ItemTile(store: s, it: i, dense: true),
        ], icon: Icons.error_outline, iconColor: scheme.error),
      LabelCard(store: s),
      if (nowPick != null)
        _section(
          context,
          'Do this now',
          [
            ItemTile(store: s, it: nowPick, dense: true),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                '${(now0.confidence * 100).round()}% sure this is the best use of now.'
                '${now0.probs.length > 1 ? ' Next: ${s.byId('items', int.parse(now0.probs.keys.elementAt(1)))?['title']}' : ''}',
                style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
          icon: Icons.bolt,
          iconColor: scheme.primary,
          trailing: IconButton(
            tooltip: 'Decide something',
            icon: const Icon(Icons.balance),
            onPressed: () => _open(context, DecidePage(store: s)),
          ),
        ),
      if (countdowns.isNotEmpty || s.list('tx').isNotEmpty)
        Row(
          children: [
            if (s.list('tx').isNotEmpty)
              _stat(context, s.money(spentToday), 'spent today', Icons.account_balance_wallet_outlined,
                  () => _open(context, MoneyPage(store: s))),
            if (countdowns.isNotEmpty && s.list('tx').isNotEmpty) const SizedBox(width: 12),
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
    ];
  }

  num _spentToday() {
    final today = dayKey(DateTime.now());
    num spent = 0;
    for (final t in s.list('tx').where((t) => t['type'] == 'expense')) {
      if (dayKey(fromMs(t['ts'] as int)) == today) spent += t['amount'] as num;
    }
    return spent;
  }

  void _openToday(BuildContext context) {
    Haptics.tick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListenableBuilder(
          listenable: s,
          builder: (ctx, _) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text('Today', style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: 8),
              ..._today(ctx),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final now = DateTime.now();
    final today = dayKey(now);
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final todays = s.list('items').where((i) {
      final w = i['when'] as int?;
      return i['status'] == 'open' && w != null && dayKey(fromMs(w)) == today;
    }).toList();
    final inbox = s.list('inbox').length;
    final warn = _overbooked(todays.where((i) => (i['when'] as int) >= now.millisecondsSinceEpoch || i['allDay'] == true).toList());
    final now0 = Decide.whatNow(s.list('items'), now);
    final nowPick = now0.pick == 'nothing' ? null : s.byId('items', int.parse(now0.pick));
    final chats = s.list('captures').where((c) => c['source'] != 'journal').toList();
    final shown = chats.length > 200 ? chats.sublist(chats.length - 200) : chats;

    // Small things worth a glance, as chips under the day strip; tap for the full Today panel.
    final chips = <Widget>[
      if (!AI.available(s))
        _chip(context, Icons.key_outlined, 'Set up an AI', scheme.tertiary, () => _open(context, SettingsPage(store: s))),
      if (inbox > 0)
        _chip(context, Icons.inbox_outlined, '$inbox to review', scheme.primary, () => _open(context, InboxPage(store: s))),
      if (warn != null) _chip(context, Icons.warning_amber_rounded, 'Busy day', scheme.error, () => _open(context, PlanDayPage(store: s))),
      if (nowPick != null) _chip(context, Icons.bolt, 'Now: ${nowPick['title']}', scheme.primary, () => _openToday(context)),
      if (s.list('tx').isNotEmpty)
        _chip(context, Icons.account_balance_wallet_outlined, '${s.money(_spentToday())} today', null, () => _open(context, MoneyPage(store: s))),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(children: [
            Expanded(
              child: Text(
                now.hour < 12 ? 'Good morning' : (now.hour < 17 ? 'Good afternoon' : 'Good evening'),
                style: tt.headlineSmall,
              ),
            ),
            TextButton.icon(
              onPressed: () => _openToday(context),
              icon: const Icon(Icons.dashboard_outlined, size: 18),
              label: const Text('Today'),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DayRibbon(
            now: now,
            items: s.list('items').where((i) {
              final w = i['when'] as int?;
              return w != null &&
                  i['allDay'] != true &&
                  (i['status'] == 'open' || i['status'] == 'done') &&
                  dayKey(fromMs(w)) == today;
            }).toList(),
            onTap: () => _openToday(context),
          ),
        ),
        if (chips.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: chips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => chips[i],
            ),
          ),
        const Divider(height: 8),
        Expanded(
          child: shown.isEmpty
              ? _emptyChat(context)
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final c = shown[shown.length - 1 - i];
                    final older = i + 1 < shown.length ? shown[shown.length - 2 - i] : null;
                    final day = dayKey(fromMs(c['ts'] as int));
                    final newDay = older == null || dayKey(fromMs(older['ts'] as int)) != day;
                    return Column(children: [
                      if (newDay) _daySeparator(context, c['ts'] as int),
                      _message(context, c),
                    ]);
                  },
                ),
        ),
        _composer(context),
      ],
    );
  }

  Widget _chip(BuildContext context, IconData icon, String label, Color? color, VoidCallback onTap) => ActionChip(
        avatar: Icon(icon, size: 16, color: color),
        label: Text(label, overflow: TextOverflow.ellipsis),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
      );

  Widget _daySeparator(BuildContext context, int ts) {
    final d = fromMs(ts);
    final now = DateTime.now();
    final label = dayKey(d) == dayKey(now)
        ? 'Today'
        : dayKey(d) == dayKey(now.subtract(const Duration(days: 1)))
            ? 'Yesterday'
            : '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }

  Widget _emptyChat(BuildContext context) {
    const ideas = [
      'Remind me to call Ammu at 8 pm',
      'Spent 250 on lunch',
      'What do I have tomorrow?',
      'Should I study or rest tonight?',
    ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        const Center(child: ShapeIcon(Icons.auto_awesome, size: 64)),
        const SizedBox(height: 16),
        Text('Tell Jarvis anything', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Plans, money, how you feel, or a question. It sorts it into the right place and answers here.',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final i in ideas) ActionChip(label: Text(i), onPressed: () => setState(() => _ctrl.text = i)),
        ]),
      ],
    );
  }

  Widget _composer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
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
      ),
    );
  }

  /// One exchange: what you said (right), and Jarvis's answer with what it did (left).
  Widget _message(BuildContext context, Rec c) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final small = tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final maxW = MediaQuery.of(context).size.width * 0.8;
    final image = c['image'] as String?;
    final mine = Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onLongPress: () => _messageMenu(context, c),
        child: Container(
          constraints: BoxConstraints(maxWidth: maxW),
          margin: const EdgeInsets.only(top: 4, bottom: 4),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (image != null && !kIsWeb && File(image).existsSync())
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(image), height: 160)),
              ),
            Text('${c['raw']}', style: tt.bodyLarge?.copyWith(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 4),
            Text('${clock(c['ts'] as int)}${c['edited'] == true ? ', edited' : ''}',
                style: tt.labelSmall?.copyWith(color: scheme.onPrimaryContainer.withValues(alpha: 0.7))),
          ]),
        ),
      ),
    );
    return Column(children: [mine, _answer(context, c, maxW, small)]);
  }

  Widget _answer(BuildContext context, Rec c, double maxW, TextStyle? small) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final status = c['status'] as String;
    final msg = (c['msg'] as String?) ?? '';
    final reply = c['reply'] as String?;
    final action = s.byId('actions', c['actionId'] as int?);
    final results = action == null || action['undone'] == true ? const <Widget>[] : _results(context, action);
    final past = ((c['past'] as List?) ?? const []).map((e) => e.toString()).toList();
    final via = c['via'] as String?;
    final text = status == 'pending'
        ? null
        : reply ?? (results.isEmpty && msg.isNotEmpty ? msg : (results.isEmpty ? 'Noted.' : null));
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(top: 4, right: 8), child: ShapeIcon(Icons.auto_awesome, size: 28)),
        Flexible(
          child: Container(
            constraints: BoxConstraints(maxWidth: maxW),
            margin: const EdgeInsets.only(top: 4, bottom: 8),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (status == 'pending')
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Flexible(child: Text(msg.isNotEmpty ? msg : 'Thinking…', style: small)),
                ]),
              if (text != null) Text(text, style: tt.bodyLarge),
              if (results.isNotEmpty) ...[
                if (text != null) const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: results),
              ],
              for (final p in past) Padding(padding: const EdgeInsets.only(top: 4), child: Text(p, style: small?.copyWith(fontStyle: FontStyle.italic))),
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (via != null && status != 'pending')
                  Text(via == 'phone' ? 'on this phone' : (via == 'ai' ? 'AI' : via), style: small),
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
                if (action != null && action['undone'] == true) Padding(padding: const EdgeInsets.only(left: 8), child: Text('Undone', style: small)),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  /// What a note created or changed, as chips you tap to open and edit.
  List<Widget> _results(BuildContext context, Rec action) {
    final out = <Widget>[];
    final seen = <String>{};
    for (final op in (action['undo'] as List).cast<Rec>()) {
      final col = op['col'] as String;
      final id = op['op'] == 'rm' ? op['id'] as int? : (op['rec'] as Rec?)?['id'] as int?;
      if (id == null || !seen.add('$col$id')) continue;
      final r = s.byId(col, id);
      if (r == null) continue;
      final (icon, label, VoidCallback? open) = switch (col) {
        'items' => (
            r['kind'] == 'event' ? Icons.event : (r['kind'] == 'alarm' ? Icons.alarm : Icons.check_box_outline_blank),
            '${r['title']}${r['when'] == null ? '' : ', ${niceWhen(r['when'] as int)}'}',
            () => showTaskSheet(context, s, item: r),
          ),
        'tx' => (Icons.payments_outlined, '${r['note'] ?? r['cat'] ?? 'Money'} ${s.money(r['amount'] as num)}', () => showTxSheet(context, s, tx: r)),
        'habits' => (Icons.local_fire_department_outlined, '${r['name']}', () => _open(context, HabitPage(store: s, id: id))),
        'countdowns' => (Icons.hourglass_bottom, '${r['title']}', () => _open(context, CountdownPage(store: s))),
        'promises' => (Icons.handshake_outlined, 'Promise to ${r['person']}', () => _open(context, PromisesPage(store: s))),
        'decisions' => (Icons.history_edu_outlined, '${r['decision']}', () => _open(context, DecisionsPage(store: s))),
        'inbox' => (Icons.inbox_outlined, 'To review', () => _open(context, InboxPage(store: s))),
        _ => (Icons.check, col, null),
      };
      out.add(ActionChip(
        avatar: Icon(icon, size: 16),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(label, overflow: TextOverflow.ellipsis),
        ),
        onPressed: open,
      ));
    }
    return out;
  }

  /// Hold a message: change it (Jarvis redoes it), copy it, or delete it.
  Future<void> _messageMenu(BuildContext context, Rec c) async {
    Haptics.tick();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit and redo'), onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(leading: const Icon(Icons.copy), title: const Text('Copy'), onTap: () => Navigator.pop(ctx, 'copy')),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete'), onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (!context.mounted) return;
    final action = s.byId('actions', c['actionId'] as int?);
    switch (choice) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: '${c['raw']}'));
      case 'delete':
        Haptics.warn();
        if (action != null && action['undone'] != true) await s.undo(action['id'] as int);
        s.removeRec('captures', c, 'Deleted note: ${c['raw']}');
      case 'edit':
        final ctrl = TextEditingController(text: '${c['raw']}');
        final text = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Edit'),
            content: TextField(controller: ctrl, autofocus: true, minLines: 1, maxLines: 6),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Redo')),
            ],
          ),
        );
        if (text == null || text.isEmpty || text == c['raw']) return;
        // Take back what the old wording did, then let Jarvis read the new one.
        if (action != null && action['undone'] != true) await s.undo(action['id'] as int);
        c
          ..['raw'] = text
          ..['cleaned'] = text
          ..['status'] = 'pending'
          ..['edited'] = true
          ..remove('msg')
          ..remove('reply')
          ..remove('actionId')
          ..remove('via');
        s.save();
        Haptics.tap();
        await Brain.drain(s);
    }
  }
}

/// Puts a phone action into the chat as a finished exchange.
void logCommand(Store s, String said, String did, {int? ts}) {
  s.list('captures').add({
    'id': s.nextId(),
    'ts': ts ?? DateTime.now().millisecondsSinceEpoch,
    'raw': said,
    'cleaned': said,
    'source': 'in-app',
    'status': 'done',
    'reply': did,
    'via': 'phone',
  });
  s.save();
}
