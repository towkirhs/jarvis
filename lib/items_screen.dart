import 'dart:math';

import 'package:flutter/material.dart';

import 'cal_event.dart';
import 'cal_grid.dart';
import 'cal_index.dart';
import 'cal_quick.dart';
import 'clock.dart';
import 'haptics.dart';
import 'habits_screen.dart';
import 'month_view.dart';
import 'journal_screen.dart' show DayPage, openEntryEditor;
import 'main_nav.dart';
import 'plan_day_page.dart';
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

/// Passes a sideways swipe that goes past the first or last of its child's pages on to the app's main tabs.
class EdgeSwipe extends StatefulWidget {
  const EdgeSwipe({super.key, required this.child});
  final Widget child;

  @override
  State<EdgeSwipe> createState() => _EdgeSwipeState();
}

class _EdgeSwipeState extends State<EdgeSwipe> {
  double _over = 0;

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth != 0 || n.metrics.axis != Axis.horizontal) return false;
          if (n is OverscrollNotification && n.dragDetails != null) _over += n.overscroll;
          if (n is ScrollEndNotification) {
            if (_over.abs() > 24) MainNav.step?.call(_over > 0 ? 1 : -1);
            _over = 0;
          }
          return false;
        },
        child: widget.child,
      );
}

/// The Plan tab: List, Calendar and Eisenhower Matrix views of the same items.
class ItemsScreen extends StatelessWidget {
  const ItemsScreen({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          // On the calendar the button opens the small add sheet, on the other tabs the full form.
          floatingActionButton: Builder(builder: (ctx) {
            final tabs = DefaultTabController.of(ctx);
            return AnimatedBuilder(
              animation: tabs,
              builder: (ctx, _) => FloatingActionButton(
                onPressed: () {
                  if (tabs.index != 1) {
                    showTaskSheet(ctx, store);
                    return;
                  }
                  final t = DateTime.now().add(const Duration(hours: 1));
                  showQuickAdd(ctx, store, day: t, at: TimeOfDay(hour: t.hour, minute: 0));
                },
                child: const Icon(Icons.add),
              ),
            );
          }),
          body: Column(
            children: [
              const TabBar(tabs: [Tab(text: 'List'), Tab(text: 'Calendar'), Tab(text: 'Matrix')]),
              Expanded(
                child: EdgeSwipe(
                  // Swipe between List, Calendar and Matrix; past the first or last, on to the app's next tab.
                  // Over the calendar's hour grid a swipe changes the days instead.
                  child: TabBarView(
                    physics: const ClampingScrollPhysics(),
                    children: [
                      _ListView(store: store),
                      _CalendarView(store: store),
                      _MatrixView(store: store),
                    ],
                  ),
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
      if (w != null) it['allDay'] == true ? niceDay(w) : niceWhen(w),
      if (it['repeat'] != null) repeatNames[it['repeat']]!,
      if (it['untilDone'] == true) 'daily until done',
      if (est != null) fmtMinutes(est),
      if (it['dur'] != null) fmtMinutes(it['dur'] as int),
      if (postponed > 0) 'postponed ${postponed}x',
      if (started) 'started',
      if ((it['list'] ?? 'Inbox') != 'Inbox') '${it['list']}',
      if (it['place'] != null)
        '${it['placeWhen'] == 'leave' ? 'leaving' : 'at'} ${Clock.place(store.list('places'), it['place'])?['name'] ?? 'a place'}',
    ].join('  ·  ');
    final body = InkWell(
        borderRadius: BorderRadius.circular(12),
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
                    onPressed: open
                        ? () {
                            Haptics.success();
                            store.markDone(it);
                          }
                        : null,
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
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    onSelected: (v) => _itemAction(context, store, it, v),
                    itemBuilder: (_) => [
                      if (open) const PopupMenuItem(value: 'done', child: Text('Done')),
                      if (open && it['kind'] == 'task' && !started)
                        const PopupMenuItem(value: 'start', child: Text('Start (track time)')),
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      if (open && w != null) const PopupMenuItem(value: 'snooze', child: Text('Snooze 1 hour')),
                      if (open) const PopupMenuItem(value: 'tomorrow', child: Text('Move to tomorrow')),
                      if (!open) const PopupMenuItem(value: 'reopen', child: Text('Mark not done')),
                      if (open) const PopupMenuItem(value: 'archive', child: Text('Archive')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
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
      );
    // Inside another card (Home, calendar) a row is flat; in lists it is its own card.
    return dense ? body : Card(child: body);
  }
}

Future<void> _itemAction(BuildContext context, Store store, Rec it, String v) async {
  {
    final w = it['when'] as int?;
    switch (v) {
      case 'done':
        Haptics.success();
        await store.markDone(it);
      case 'start':
        await store.updateRec('items', it, 'Started: ${it['title']}',
            (r) => r['startedAt'] = DateTime.now().millisecondsSinceEpoch);
      case 'edit':
        await showTaskSheet(context, store, item: it);
      case 'snooze':
        await store.updateRec('items', it, 'Snoozed: ${it['title']}', (r) {
          final base = max(w!, DateTime.now().millisecondsSinceEpoch);
          r['when'] = base + 3600000;
        });
      case 'tomorrow':
        await store.updateRec('items', it, 'Moved to tomorrow: ${it['title']}', (r) {
          final d = w != null ? fromMs(w) : DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 9);
          final now = DateTime.now();
          r['when'] = DateTime(now.year, now.month, now.day + 1, d.hour, d.minute).millisecondsSinceEpoch;
          r['postponed'] = ((r['postponed'] as int?) ?? 0) + 1;
          r['nid'] ??= store.nextId();
        });
      case 'reopen':
        await store.updateRec('items', it, 'Reopened: ${it['title']}', (r) {
          r['status'] = 'open';
          r['doneAt'] = null;
        });
      case 'archive':
        await store.updateRec('items', it, 'Archived: ${it['title']}', (r) => r['status'] = 'cancelled');
      case 'delete':
        Haptics.warn();
        store.removeRec('items', it, 'Deleted: ${it['title']}');
    }
  }
}

const _groups = ['Overdue', 'Today', 'Tomorrow', 'Next 7 days', 'Later', 'No date'];

/// Which heading an open item goes under in the list.
String _groupOf(Rec it) {
  final w = it['when'] as int?;
  if (w == null) return 'No date';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = fromMs(w);
  final days = DateTime(d.year, d.month, d.day).difference(today).inDays;
  if (days < 0 || (days == 0 && it['allDay'] != true && d.isBefore(now))) return 'Overdue';
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days < 7) return 'Next 7 days';
  return 'Later';
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
          final hasOverdue = open.any((i) => _groupOf(i) == 'Overdue');
          final habitRows = <Widget>[
            if ((_filter == 'All' || _filter == 'Today') && s.habitsDueToday().isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                child: Text('Habits today',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
              ),
              for (final h in s.habitsDueToday()) HabitTodayRow(store: s, habit: h),
            ],
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
            children: [
              Wrap(spacing: 8, children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.auto_awesome_motion),
                  label: const Text('Plan my day'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlanDayPage(store: s))),
                ),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final f in filters)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
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
              if (!hasOverdue) ...habitRows,
              if (open.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing here. Tap + or tell Jarvis.')),
              for (final g in _groups)
                if (open.any((i) => _groupOf(i) == g)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                    child: Text(
                      g,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: g == 'Overdue' ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ),
                  for (final it in open.where((i) => _groupOf(i) == g)) ItemTile(store: s, it: it),
                  // What is behind comes first; today's habits follow it.
                  if (g == 'Overdue') ...habitRows,
                ],
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
  /// The first day on show. It drives the title; swiping the grid keeps it up to date.
  DateTime _day = DateTime.now();

  /// How many days are on show: 1, 2, 3, 7 (a week), 15 or 30; 0 is the month.
  int _n = 3;

  /// Hours run across the screen (one row per day) instead of down it.
  bool _across = false;

  /// Events at the same time lie on top of each other instead of side by side.
  bool _stack = false;

  /// One day as a list, opened by tapping a day.
  bool _list = false;
  final _grid = GlobalKey<TimeGridState>();

  /// Where the grid opens. It only changes when the view or the day is chosen, never by swiping.
  late DateTime _anchor = _startFor(_day);
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    // Your default view: "days|across|stack", saved from the view sheet.
    final p = (widget.store.local('calView') ?? '').split('|');
    if (p.length == 3) {
      _n = int.tryParse(p[0]) ?? 3;
      _across = p[1] == '1';
      _stack = p[2] == '1';
    }
  }

  /// The hour grid with a column per day: up to a week, hours running down.
  bool get _isGrid => !_list && !_across && _n >= 1 && _n <= 7;

  /// How many days one step moves.
  int get _step => _list ? 1 : (_n == 0 ? 30 : _n);

  DateTime _startFor(DateTime d) => _n == 7 ? widget.store.mondayOf(d) : DateTime(d.year, d.month, d.day);

  /// Opens the calendar on [d].
  void _jump(DateTime d) => setState(() {
        _day = d;
        _anchor = _startFor(d);
        _seq++;
      });

  /// The arrows: a page of the grid, a month in the month view, otherwise a few days.
  void _go(int dir) {
    if (_isGrid) {
      _grid.currentState?.pageBy(dir);
      return;
    }
    setState(() => _day = _n == 0 && !_list
        ? DateTime(_day.year, _day.month + dir, 1)
        : DateTime(_day.year, _day.month, _day.day + dir * _step));
  }

  void _openDay(DateTime d) => setState(() {
        _day = d;
        _list = true;
      });

  void _show({int? n, bool? across, bool? stack}) => setState(() {
        _n = n ?? _n;
        _across = across ?? _across;
        _stack = stack ?? _stack;
        _list = false;
        _anchor = _startFor(_day);
        _seq++;
      });

  static const _spans = [(1, '1 day'), (2, '2 days'), (3, '3 days'), (7, 'Week'), (15, '15 days'), (30, '30 days'), (0, 'Month')];

  /// Today, another date, how many days to show, which way the hours run, and your default.
  Future<void> _viewSheet() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) {
            final tt = Theme.of(ctx).textTheme;
            final scheme = Theme.of(ctx).colorScheme;
            void show({int? n, bool? across, bool? stack}) {
              Haptics.tap();
              _show(n: n, across: across, stack: stack);
              setS(() {});
            }

            Widget label(String text) => Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 8),
                  child: Text(text, style: tt.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
                );
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.today),
                        label: const Text('Go to today'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _jump(DateTime.now());
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.event),
                        label: const Text('Pick a date'),
                        onPressed: () async {
                          final d = await showDatePicker(context: ctx, initialDate: _day, firstDate: DateTime(_day.year - 5), lastDate: DateTime(_day.year + 5));
                          if (d == null || !ctx.mounted) return;
                          Navigator.pop(ctx);
                          _jump(d);
                        },
                      ),
                    ),
                  ]),
                  label('Show'),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final (n, text) in _spans)
                      ChoiceChip(label: Text(text), showCheckmark: false, selected: !_list && _n == n, onSelected: (_) => show(n: n)),
                  ]),
                  label('Layout'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hours across'),
                    subtitle: Text(_n == 0 ? 'Not for the month' : (_across ? 'Each day is a row, hours run sideways' : 'Off: hours run down the screen')),
                    value: _across && _n != 0,
                    onChanged: _n == 0 ? null : (v) => show(across: v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Overlap events'),
                    subtitle: Text(_stack ? 'Events at the same time lie on top of each other' : 'Off: events at the same time sit side by side'),
                    value: _stack,
                    onChanged: (v) => show(stack: v),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        await widget.store.setLocal('calView', '$_n|${_across ? 1 : 0}|${_stack ? 1 : 0}');
                        Haptics.success();
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The calendar will open like this from now on.')));
                        }
                      },
                      child: const Text('Use this as my default'),
                    ),
                  ),
                ]),
              ),
            );
          },
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final s = widget.store;
          final tt = Theme.of(context).textTheme;
          final start = DateTime(_day.year, _day.month, _day.day);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${_months[_day.month - 1]} ${_day.year}', style: tt.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    IconButton(tooltip: 'Previous', icon: const Icon(Icons.chevron_left), onPressed: () => _go(-1)),
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), visualDensity: VisualDensity.compact),
                      onPressed: _viewSheet,
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Today'), Icon(Icons.arrow_drop_down, size: 20)]),
                    ),
                    IconButton(tooltip: 'Next', icon: const Icon(Icons.chevron_right), onPressed: () => _go(1)),
                    IconButton(
                      tooltip: 'Plan this day',
                      icon: const Icon(Icons.auto_awesome_motion),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlanDayPage(store: s, day: _day))),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _list
                    ? _dayList(context, s)
                    : _n == 0
                        ? MonthView(store: s, month: _day, onDayTap: _openDay)
                        : _across
                            ? TimelineGrid(store: s, start: _n == 7 ? s.mondayOf(_day) : start, count: _n, onDayTap: _openDay)
                            : _n > 7
                                ? _agenda(context, s, _n)
                                : KeyedSubtree(
                                    key: ValueKey('$_n/$_stack/$_seq'),
                                    child: TimeGrid(
                                      key: _grid,
                                      store: s,
                                      anchor: _anchor,
                                      count: _n,
                                      stack: _stack,
                                      onVisible: (d) => setState(() => _day = d),
                                      onDayTap: _openDay,
                                    ),
                                  ),
              ),
            ],
          );
        },
      );

  /// A row for something on a day. A repeat's later dates and the later days of a long item open their view.
  Widget _entryTile(BuildContext context, Store s, CalEntry e) {
    if (!e.repeated && e.firstDay) return ItemTile(store: s, it: e.item, dense: true);
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Icon(e.repeated ? Icons.repeat : Icons.event, color: eventColor(e.item, scheme)),
      title: Text(e.item['title'] as String),
      subtitle: Text(eventWhen(e)),
      onTap: () => showEventView(context, s, e),
    );
  }

  /// [n] days from [_day] down the screen, one heading per day that has something on it.
  Widget _agenda(BuildContext context, Store s, int n) {
    final from = DateTime(_day.year, _day.month, _day.day);
    final index = CalIndex.build(s.calendarItems, from, DateTime(from.year, from.month, from.day + n - 1));
    final countdowns = CalIndex.countdowns(s);
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final todayKey = dayKey(DateTime.now());
    final rows = <Widget>[];
    for (var i = 0; i < n; i++) {
      final d = DateTime(from.year, from.month, from.day + i);
      final key = dayKey(d);
      final entries = index[key] ?? const <CalEntry>[];
      final cds = countdowns[key] ?? const <Rec>[];
      if (entries.isEmpty && cds.isEmpty) continue;
      rows.add(InkWell(
        onTap: () => _openDay(d),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Text(
            '${key == todayKey ? 'Today, ' : ''}${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}',
            style: tt.titleSmall?.copyWith(color: key == todayKey ? scheme.primary : null),
          ),
        ),
      ));
      for (final c in cds) {
        rows.add(ListTile(dense: true, leading: const Icon(Icons.hourglass_bottom), title: Text(c['title'] as String)));
      }
      for (final e in entries) {
        rows.add(_entryTile(context, s, e));
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
      children: rows.isEmpty ? [Padding(padding: const EdgeInsets.all(16), child: Text('Nothing in these $n days.'))] : rows,
    );
  }

  Widget _dayList(BuildContext context, Store s) {
    final monday = s.mondayOf(_day);
    final week = [for (var i = 0; i < 7; i++) DateTime(monday.year, monday.month, monday.day + i)];
    final key = dayKey(_day);
    final todayKey = dayKey(DateTime.now());
    final entries = CalIndex.build(s.calendarItems, _day, _day)[key] ?? const <CalEntry>[];
    final countdowns = CalIndex.countdowns(s)[key] ?? const <Rec>[];
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
      children: [
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
                            color: dayKey(d) == key ? scheme.onPrimary : (dayKey(d) == todayKey ? scheme.primary : null),
                            fontWeight: dayKey(d) == todayKey ? FontWeight.bold : null,
                          ),
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
        if (entries.isEmpty && countdowns.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing on this day.')),
        for (final e in entries) _entryTile(context, s, e),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: Text('Add on $key'),
            onPressed: () => showTaskSheet(context, s, day: _day),
          ),
        ),
        const SizedBox(height: 8),
        // The day's journal: what you wrote, or a way to write it.
        Builder(builder: (context) {
          final written = s.entriesOn(key);
          return Card(
            child: ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(written.isEmpty ? 'Journal' : 'Journal: ${written.length} entr${written.length == 1 ? 'y' : 'ies'}'),
              subtitle: Text(
                written.isEmpty ? 'Write about this day' : '${written.first['text']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => written.isEmpty
                  ? openEntryEditor(context, s, day: _day)
                  : Navigator.push(context, MaterialPageRoute(builder: (_) => DayPage(store: s, day: key))),
            ),
          );
        }),
      ],
    );
  }
}

/// A week with the hours running left to right: one row per day, scroll sideways through the day.
class TimelineGrid extends StatefulWidget {
  const TimelineGrid({super.key, required this.store, required this.start, required this.onDayTap, this.count = 7});
  final Store store;
  final DateTime start;

  /// How many days (rows) it shows.
  final int count;
  final void Function(DateTime day) onDayTap;

  @override
  State<TimelineGrid> createState() => _TimelineGridState();
}

class _TimelineGridState extends State<TimelineGrid> {
  static const _hourW = 64.0;
  static const _labelW = 52.0;
  static const _barH = 24.0;
  late final ScrollController _sideways =
      ScrollController(initialScrollOffset: _hourW * ((DateTime.now().hour - 1).clamp(0, 18)));

  @override
  void dispose() {
    _sideways.dispose();
    super.dispose();
  }

  int _minutes(Rec it) => ((it['dur'] ?? it['est'] ?? 60) as int).clamp(15, 24 * 60);

  /// Stacks overlapping bars in rows: returns the row of each item and how many rows the day needs.
  (Map<int, int>, int) _rows(List<CalEntry> items) {
    final out = <int, int>{};
    final ends = <int>[];
    for (final e in items) {
      final it = e.item;
      final st = e.start.millisecondsSinceEpoch;
      var row = ends.indexWhere((e) => e <= st);
      if (row < 0) {
        row = ends.length;
        ends.add(0);
      }
      ends[row] = st + _minutes(it) * 60000;
      out[it['id'] as int] = row;
    }
    return (out, max(ends.length, 1));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.labelSmall;
    final grid = scheme.outlineVariant.withValues(alpha: 0.4);
    final now = DateTime.now();
    final days = [for (var i = 0; i < widget.count; i++) DateTime(widget.start.year, widget.start.month, widget.start.day + i)];
    final index = CalIndex.build(s.calendarItems, days.first, days.last);
    final perDay = [
      for (final d in days) [for (final e in index[dayKey(d)] ?? const <CalEntry>[]) if (e.item['allDay'] != true) e],
    ];
    final layouts = [for (final items in perDay) _rows(items)];
    final heights = [for (final (_, n) in layouts) max(56.0, n * (_barH + 4) + 8)];

    Widget hourLabels() => SizedBox(
          height: 24,
          child: Row(children: [
            for (var h = 0; h < 24; h++)
              SizedBox(
                width: _hourW,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(h == 0 ? '12 am' : (h == 12 ? '12 pm' : (h < 12 ? '$h am' : '${h - 12} pm')), style: small),
                ),
              ),
          ]),
        );

    Widget dayRow(int k) {
      final d = days[k];
      final (rows, _) = layouts[k];
      final isToday = dayKey(d) == dayKey(now);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (e) {
          final halfHours = (e.localPosition.dx / (_hourW / 2)).floor().clamp(0, 47);
          showQuickAdd(context, s, day: d, at: TimeOfDay(hour: halfHours ~/ 2, minute: (halfHours % 2) * 30), minutes: 60);
        },
        child: SizedBox(
          width: _hourW * 24,
          height: heights[k],
          child: Stack(children: [
            for (var h = 0; h < 24; h++)
              Positioned(
                left: h * _hourW,
                top: 0,
                bottom: 0,
                width: _hourW,
                child: DecoratedBox(
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: grid), top: BorderSide(color: grid))),
                ),
              ),
            for (final e in perDay[k])
              Builder(builder: (context) {
                final it = e.item;
                final st = e.start;
                final left = (st.hour * 60 + st.minute) / 60 * _hourW;
                final done = it['status'] == 'done';
                return Positioned(
                  left: left + 1,
                  top: 4 + rows[it['id'] as int]! * (_barH + 4),
                  width: max(_minutes(it) / 60 * _hourW - 2, 28.0),
                  height: _barH,
                  child: GestureDetector(
                    onTap: () => showEventView(context, s, e),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: eventColor(it, scheme).withValues(alpha: done ? 0.35 : 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${it['kind'] == 'alarm' ? '⏰ ' : ''}${it['title']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          decoration: done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            if (isToday)
              Positioned(
                left: (now.hour * 60 + now.minute) / 60 * _hourW - 1,
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: Colors.red),
              ),
          ]),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 80),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Day names stay put while the hours scroll.
          SizedBox(
            width: _labelW,
            child: Column(children: [
              const SizedBox(height: 24),
              for (var k = 0; k < widget.count; k++)
                InkWell(
                  onTap: () => widget.onDayTap(days[k]),
                  child: SizedBox(
                    height: heights[k],
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_weekdays[days[k].weekday - 1],
                            style: TextStyle(fontSize: 12, color: dayKey(days[k]) == dayKey(now) ? scheme.primary : null)),
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: dayKey(days[k]) == dayKey(now) ? scheme.primary : Colors.transparent,
                          child: Text('${days[k].day}',
                              style: TextStyle(
                                fontSize: 14,
                                color: dayKey(days[k]) == dayKey(now) ? scheme.onPrimary : scheme.onSurface,
                              )),
                        ),
                      ],
                    ),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _sideways,
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [hourLabels(), for (var k = 0; k < widget.count; k++) dayRow(k)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Matrix on its own page, opened from Plan my day.
class MatrixPage extends StatelessWidget {
  const MatrixPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('What matters')),
        body: _MatrixView(store: store),
      );
}

/// Eisenhower Matrix. Priority decides the quadrant: High = urgent and important,
/// Medium = important, Low = urgent, None = neither. Moving a task changes its priority.
class _MatrixView extends StatelessWidget {
  const _MatrixView({required this.store});
  final Store store;

  // (priority, title, what it means, colour)
  static const _quadrants = [
    (3, 'Do first', 'Urgent, important', Colors.red),
    (2, 'Schedule', 'Important, not urgent', Colors.orange),
    (1, 'Delegate', 'Urgent, less important', Colors.blue),
    (0, 'Eliminate', 'Neither', Colors.teal),
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final open = store.list('items').where((i) => i['status'] == 'open').toList()..sort(_byWhen);
          Widget quadrant((int, String, String, MaterialColor) q) {
            final (p, name, meaning, color) = q;
            final items = open.where((i) => ((i['priority'] as int?) ?? 0) == p).toList();
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                    Text(meaning, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                                            onTap: () {
                                              Haptics.success();
                                              store.markDone(it);
                                            },
                                            child: const Icon(Icons.check_box_outline_blank, size: 20),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('${it['title']}'),
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
                const Text('Hold a task to move it to another box.'),
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
          for (final (p, name, meaning, color) in _quadrants)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p),
              child: Text('$name · $meaning', style: TextStyle(color: color)),
            ),
        ],
      ),
    );
    if (p == null) return;
    await store.updateRec('items', it, 'Moved ${it['title']} to ${priorityNames[p]} priority', (r) => r['priority'] = p);
  }
}
