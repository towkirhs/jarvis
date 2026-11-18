import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'app_alarms.dart';
import 'day_log.dart';
import 'day_start_menu.dart';
import 'done_sheet.dart';
import 'haptics.dart';
import 'native.dart';
import 'plan_day_page.dart';
import 'store.dart';

/// Your day as it really went: how the plan is going, what you are doing now, a timeline, and time in apps.
class DayPage extends StatefulWidget {
  const DayPage({super.key, required this.store, this.day});
  final Store store;
  final DateTime? day;

  @override
  State<DayPage> createState() => _DayPageState();
}

class _DayPageState extends State<DayPage> with WidgetsBindingObserver {
  Store get store => widget.store;
  late DateTime _day;
  final _now = TextEditingController();
  List<AppSession> _apps = const [];
  bool? _usage;

  bool get _isToday {
    final n = DayStart.now();
    return _day.year == n.year && _day.month == n.month && _day.day == n.day;
  }

  @override
  void initState() {
    super.initState();
    final d = widget.day ?? DayStart.now();
    _day = DateTime(d.year, d.month, d.day);
    WidgetsBinding.instance.addObserver(this);
    _loadApps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _now.dispose();
    super.dispose();
  }

  // Back from Android's Usage access screen, or from another app: read app time again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadApps();
  }

  Future<void> _loadApps() async {
    if (kIsWeb) return;
    final ok = await Native.usageAccess();
    final raw = ok ? await Native.appSessions(_day.add(Duration(minutes: DayStart.minutes)), _day.add(Duration(days: 1, minutes: DayStart.minutes))) : const <Map>[];
    if (!mounted) return;
    setState(() {
      _usage = ok;
      _apps = raw.map(AppSession.from).whereType<AppSession>().toList();
    });
  }

  void _goTo(int days) {
    setState(() {
      _day = DateTime(_day.year, _day.month, _day.day + days);
      _apps = const [];
    });
    _loadApps();
  }

  Future<void> _log(String text) async {
    final act = NowLog.parse(text, forced: true);
    if (act == null) return;
    Haptics.success();
    _now.clear();
    FocusScope.of(context).unfocus();
    final said = await store.logNow(act);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(said)));
  }

  static String _clock(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'am' : 'pm'}';
  }

  static String _dayName(DateTime d) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final n = DayStart.now();
    final diff = d.difference(DateTime(n.year, n.month, n.day)).inDays;
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }

  static IconData _icon(String kind) => switch (kind) {
        'wake' => Icons.wb_sunny_outlined,
        'sleep' => Icons.bedtime_outlined,
        'back' => Icons.home_outlined,
        'finish' || 'done' => Icons.check_circle_outline,
        'skip' => Icons.redo,
        'other' => Icons.swap_horiz,
        'app' => Icons.phone_android,
        'apps' => Icons.bar_chart,
        _ => Icons.play_circle_outline,
      };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final scheme = Theme.of(context).colorScheme;
          final tt = Theme.of(context).textTheme;
          final moments = DayLog.timeline(_day, log: store.list('log'), items: store.list('items'), apps: _apps);
          return Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              title: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'Previous day', icon: const Icon(Icons.chevron_left), onPressed: () => _goTo(-1)),
                Flexible(child: Text(_dayName(_day), style: tt.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                IconButton(tooltip: 'Next day', icon: const Icon(Icons.chevron_right), onPressed: _isToday ? null : () => _goTo(1)),
              ]),
              actions: [DayStartMenu(store: store)],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                Text('Your day', style: tt.headlineSmall),
                const SizedBox(height: 4),
                Text('What really happened, next to what you planned.', style: TextStyle(color: scheme.onSurfaceVariant)),
                if (_isToday) ...[
                  const SizedBox(height: 12),
                  _planCard(context),
                  const SizedBox(height: 16),
                  _nowField(context),
                ],
                const SizedBox(height: 20),
                Text('Timeline', style: tt.titleMedium),
                const SizedBox(height: 4),
                if (moments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Nothing yet. Tell Jarvis "started gym" or "back home", answer the check-ins when planned blocks end, '
                      'and allow usage access to see time in apps.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                for (final m in moments) _moment(context, m),
                if (!kIsWeb) ...[
                  const SizedBox(height: 20),
                  _appsSection(context),
                ],
                if (!kIsWeb) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ask when a planned block ends'),
                    subtitle: const Text('"Finished it?" with Done, 15 more min, or Skipped / what you did instead'),
                    value: store.checkIns,
                    onChanged: (v) {
                      Haptics.toggle(v);
                      store.setCheckIns(v);
                    },
                  ),
                ],
              ],
            ),
          );
        },
      );

  Widget _planCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final check = PlanCheck.of(store.list('items'), DateTime.now(), dayKey(_day));
    final late = check.late.isNotEmpty;
    final ink = late ? scheme.onTertiaryContainer : scheme.onSurface;
    void open({bool replan = false}) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => PlanDayPage(store: store, replan: replan)));
    return Card(
      margin: EdgeInsets.zero,
      color: late ? scheme.tertiaryContainer : scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(check.summary, style: tt.titleMedium?.copyWith(color: ink)),
          if (check.planned > 0) ...[
            const SizedBox(height: 2),
            Text(
              '${check.done} done · ${check.skipped} skipped · ${check.toCome} still to come',
              style: tt.bodyMedium?.copyWith(color: ink.withValues(alpha: 0.8)),
            ),
          ],
          for (final i in check.late) ...[
            const SizedBox(height: 10),
            Text('${i['title']}', style: tt.titleSmall?.copyWith(color: ink)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, children: [
              ActionChip(
                avatar: const Icon(Icons.check, size: 18),
                label: const Text('Done'),
                onPressed: () {
                  Haptics.success();
                  store.answerCheck(i, 'done', null, DateTime.now().millisecondsSinceEpoch);
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.redo, size: 18),
                label: const Text('Skipped'),
                onPressed: () {
                  Haptics.tap();
                  store.answerCheck(i, 'skip', null, DateTime.now().millisecondsSinceEpoch);
                },
              ),
            ]),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: check.planned == 0
                ? TextButton.icon(icon: const Icon(Icons.auto_awesome_motion), label: const Text('Plan my day'), onPressed: open)
                : TextButton.icon(
                    icon: const Icon(Icons.auto_fix_high),
                    label: Text(late || check.skipped > 0 ? 'Replan the rest' : 'Open the plan'),
                    onPressed: () => open(replan: late || check.skipped > 0),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _nowField(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    const quick = ['Woke up', 'Back home', 'Going to sleep'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('What are you doing now?', style: tt.titleMedium),
      const SizedBox(height: 8),
      TextField(
        controller: _now,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: _log,
        decoration: InputDecoration(
          hintText: 'Started gym, reading, back from class…',
          suffixIcon: IconButton(tooltip: 'Note it', icon: const Icon(Icons.send), onPressed: () => _log(_now.text)),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final q in quick) ActionChip(label: Text(q), onPressed: () => _log(q)),
        // Your own buttons: tap to start, tap again to stop; hold to rename or remove.
        for (final a in store.list('acts')) _actChip(context, a),
        ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Button'), tooltip: 'Add your own button', onPressed: () => _editAct(null)),
      ]),
      const SizedBox(height: 4),
      TextButton.icon(
        icon: const Icon(Icons.more_time),
        label: const Text('Add something you did earlier'),
        onPressed: () {
          final n = DateTime.now();
          showDoneSheet(context, store, from: n.subtract(const Duration(hours: 1)), to: n);
        },
      ),
    ]);
  }

  Widget _actChip(BuildContext context, Rec a) {
    final run = DayLog.running(store.list('log'), a['id'] as int);
    final mins = run == null ? 0 : DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(run['at'] as int)).inMinutes;
    return GestureDetector(
      onLongPress: () => _editAct(a),
      child: FilterChip(
        avatar: Icon(run == null ? Icons.play_arrow : Icons.stop, size: 18),
        label: Text(run == null ? '${a['name']}' : '${a['name']} · ${DayLog.span(mins)}'),
        showCheckmark: false,
        selected: run != null,
        onSelected: (_) {
          Haptics.toggle(run == null);
          if (run == null) {
            store.startAct(a);
          } else {
            store.stopLog(run);
          }
        },
      ),
    );
  }

  /// Add a button ([a] null), or rename or remove one.
  Future<void> _editAct(Rec? a) async {
    final ctrl = TextEditingController(text: a == null ? '' : '${a['name']}');
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a == null ? 'Your own button' : 'Change button'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Tuition, YouTube, Study…'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          if (a != null) TextButton(onPressed: () => Navigator.pop(ctx, '\u0000'), child: const Text('Remove')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    if (res == null) return;
    if (a != null && res == '\u0000') {
      store.removeRec('acts', a, 'Removed button: ${a['name']}');
      return;
    }
    final name = res.trim();
    if (name.isEmpty) return;
    final nice = name[0].toUpperCase() + name.substring(1);
    if (a == null) {
      final r = {'id': store.nextId(), 'name': nice};
      store.list('acts').add(r);
      store.logAction('Added button: $nice', [
        {'op': 'rm', 'col': 'acts', 'id': r['id']},
      ]);
      store.save();
    } else {
      await store.updateRec('acts', a, 'Renamed button: $nice', (x) => x['name'] = nice);
    }
  }

  Widget _moment(BuildContext context, Moment m) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final mins = m.end?.difference(m.at).inMinutes;
    final faded = m.kind == 'app' || m.kind == 'apps';
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 72,
          child: Text(_clock(m.at), style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ),
        Icon(_icon(m.kind), size: 20, color: faded ? scheme.onSurfaceVariant : scheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.text, style: tt.bodyLarge?.copyWith(color: faded ? scheme.onSurfaceVariant : null)),
            if (mins != null && mins > 0)
              Text(DayLog.span(mins), style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
    final log = m.log;
    if (log == null) return row;
    // What you said, or answered at a check-in: tap to change the words or the time, copy or delete it.
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => editDone(context, store, log),
      child: row,
    );
  }

  Widget _appsSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final totals = AppSession.totals(_apps).take(6).toList();
    final most = totals.isEmpty ? 1 : totals.first.minutes;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(_isToday ? 'Apps today' : 'Apps that day', style: tt.titleMedium)),
        TextButton.icon(
          icon: const Icon(Icons.add_alarm),
          label: const Text('App alarm'),
          onPressed: () => showAppAlarmEditor(context, store),
        ),
      ]),
      if (_usage == false)
        Card(
          margin: const EdgeInsets.only(top: 4),
          color: scheme.tertiaryContainer,
          child: ListTile(
            leading: Icon(Icons.lock_open, color: scheme.onTertiaryContainer),
            title: const Text('Allow usage access'),
            subtitle: const Text('So Jarvis can note your time in apps and ring app alarms. Tap, find Jarvis, switch it on.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: Native.openUsageAccess,
          ),
        )
      else if (totals.isEmpty)
        Text('No app time noted.', style: TextStyle(color: scheme.onSurfaceVariant))
      else
        for (final t in totals)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Text(DayLog.span(t.minutes), style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: t.minutes / most,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ]),
          ),
    ]);
  }
}
