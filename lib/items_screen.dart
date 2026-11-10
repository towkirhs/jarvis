import 'dart:math';

import 'package:flutter/material.dart';

import 'clock.dart';
import 'haptics.dart';
import 'habits_screen.dart';
import 'month_view.dart';
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
                  // Sideways swipes switch the app's main tabs; these tabs switch by tapping.
                  physics: const NeverScrollableScrollPhysics(),
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
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.auto_awesome_motion),
                  label: const Text('Plan my day'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlanDayPage(store: s))),
                ),
              ),
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
  DateTime _day = DateTime.now();
  String _view = '3day'; // month, week, 3day, 2day, timeline or list

  /// How many days the arrows move by.
  int get _step => switch (_view) {
        '3day' => 3,
        '2day' => 2,
        _ => 7,
      };

  /// The arrows: a month at a time in the month view, otherwise a few days.
  void _go(int dir) => setState(() => _day = _view == 'month'
      ? DateTime(_day.year, _day.month + dir, 1)
      : DateTime(_day.year, _day.month, _day.day + dir * _step));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final s = widget.store;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
                child: Row(
                  children: [
                    Text('${_months[_day.month - 1]} ${_day.year}', style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    IconButton(tooltip: 'Previous',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _go(-1),
                    ),
                    TextButton(onPressed: () => setState(() => _day = DateTime.now()), child: const Text('Today')),
                    IconButton(tooltip: 'Next',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _go(1),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'View',
                      icon: Icon(switch (_view) {
                        'month' => Icons.calendar_view_month,
                        '3day' => Icons.view_column_outlined,
                        '2day' => Icons.view_week_outlined,
                        'timeline' => Icons.view_timeline_outlined,
                        'list' => Icons.view_agenda_outlined,
                        _ => Icons.calendar_view_week,
                      }),
                      initialValue: _view,
                      onSelected: (v) => setState(() => _view = v),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'month', child: Text('Month')),
                        PopupMenuItem(value: '2day', child: Text('2 days')),
                        PopupMenuItem(value: '3day', child: Text('3 days')),
                        PopupMenuItem(value: 'week', child: Text('Week')),
                        PopupMenuItem(value: 'timeline', child: Text('Timeline (hours across)')),
                        PopupMenuItem(value: 'list', child: Text('Day list')),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: switch (_view) {
                  'list' => _dayList(context, s),
                  'month' => MonthView(
                      store: s,
                      month: _day,
                      onDayTap: (d) => setState(() {
                        _day = d;
                        _view = 'list';
                      }),
                    ),
                  'timeline' => TimelineGrid(
                      store: s,
                      start: s.mondayOf(_day),
                      onDayTap: (d) => setState(() {
                        _day = d;
                        _view = 'list';
                      }),
                    ),
                  _ => WeekGrid(
                      store: s,
                      start: _view == 'week' ? s.mondayOf(_day) : DateTime(_day.year, _day.month, _day.day),
                      count: _step,
                      onDayTap: (d) => setState(() {
                        _day = d;
                        _view = 'list';
                      }),
                    ),
                },
              ),
            ],
          );
        },
      );

  Widget _dayList(BuildContext context, Store s) {
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
        if (items.isEmpty && countdowns.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing on this day.')),
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
  }
}

/// Google Calendar style week: one column per day, one row per hour, items drawn as blocks.
/// Tap an empty slot to add an event there; tap a block to edit it.
class WeekGrid extends StatefulWidget {
  const WeekGrid({super.key, required this.store, required this.start, this.count = 7, required this.onDayTap});
  final Store store;
  final DateTime start;
  final int count;
  final void Function(DateTime day) onDayTap;

  @override
  State<WeekGrid> createState() => _WeekGridState();
}

class _WeekGridState extends State<WeekGrid> {
  static const _hourH = 60.0;
  static const _gutter = 48.0;
  late final ScrollController _scroll =
      ScrollController(initialScrollOffset: _hourH * ((DateTime.now().hour - 2).clamp(0, 16)));

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Color _color(Rec it, ColorScheme scheme) => _colorOf(it, scheme);

  static Color _colorOf(Rec it, ColorScheme scheme) {
    final p = (it['priority'] as int?) ?? 0;
    if (p > 0) return priorityColors[p];
    return switch (it['kind']) {
      'alarm' => Colors.deepOrange,
      'task' => scheme.tertiary,
      _ => scheme.primary,
    };
  }

  /// Places overlapping blocks side by side: returns (lane, lanes) for each item.
  Map<int, (int, int)> _lanes(List<Rec> items) {
    final out = <int, (int, int)>{};
    var group = <Rec>[];
    var groupEnd = 0;
    final laneEnds = <int>[];
    void close() {
      final n = laneEnds.length;
      for (final it in group) {
        out[it['id'] as int] = (out[it['id'] as int]!.$1, n);
      }
      group = [];
      laneEnds.clear();
    }

    for (final it in items) {
      final st = it['when'] as int;
      final en = st + _minutes(it) * 60000;
      if (group.isNotEmpty && st >= groupEnd) close();
      var lane = laneEnds.indexWhere((e) => e <= st);
      if (lane < 0) {
        lane = laneEnds.length;
        laneEnds.add(en);
      } else {
        laneEnds[lane] = en;
      }
      out[it['id'] as int] = (lane, 1);
      group.add(it);
      if (en > groupEnd || group.length == 1) groupEnd = en > groupEnd ? en : groupEnd;
    }
    if (group.isNotEmpty) close();
    return out;
  }

  int _minutes(Rec it) => ((it['dur'] ?? it['est'] ?? 60) as int).clamp(15, 24 * 60);

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final scheme = Theme.of(context).colorScheme;
    final days = [for (var i = 0; i < widget.count; i++) DateTime(widget.start.year, widget.start.month, widget.start.day + i)];
    final now = DateTime.now();
    final todayKey = dayKey(now);
    final grid = scheme.outlineVariant.withValues(alpha: 0.4);

    return LayoutBuilder(builder: (context, box) {
      final colW = (box.maxWidth - _gutter) / widget.count;
      return Column(
        children: [
          // Day names and dates.
          Row(
            children: [
              const SizedBox(width: _gutter),
              for (final d in days)
                SizedBox(
                  width: colW,
                  child: InkWell(
                    onTap: () => widget.onDayTap(d),
                    child: Column(
                      children: [
                        Text(_weekdays[d.weekday - 1],
                            style: TextStyle(fontSize: 12, color: dayKey(d) == todayKey ? scheme.primary : null)),
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: dayKey(d) == todayKey ? scheme.primary : Colors.transparent,
                          child: Text('${d.day}',
                              style: TextStyle(
                                fontSize: 16,
                                color: dayKey(d) == todayKey ? scheme.onPrimary : scheme.onSurface,
                              )),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          // All-day row: countdowns that fall on each day.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: _gutter),
              for (final d in days)
                SizedBox(
                  width: colW,
                  child: Column(
                    children: [
                      for (final it in s.list('items').where((i) =>
                          i['allDay'] == true &&
                          i['status'] != 'cancelled' &&
                          i['when'] != null &&
                          dayKey(fromMs(i['when'] as int)) == dayKey(d)))
                        GestureDetector(
                          onTap: () => showTaskSheet(context, s, item: it),
                          child: Container(
                            margin: const EdgeInsets.all(1),
                            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: _color(it, scheme).withValues(alpha: it['status'] == 'done' ? 0.35 : 0.9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(it['title'] as String,
                                maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(fontSize: 11, color: Colors.white)),
                          ),
                        ),
                      for (final c in s.list('countdowns').where((c) => dayKey(s.countdownNext(c)) == dayKey(d)))
                        Container(
                          margin: const EdgeInsets.all(1),
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                          width: double.infinity,
                          decoration: BoxDecoration(color: Colors.teal, borderRadius: BorderRadius.circular(4)),
                          child: Text(c['title'] as String,
                              maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(fontSize: 11, color: Colors.white)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 80),
              child: SizedBox(
                height: _hourH * 24,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _gutter,
                      child: Stack(
                        children: [
                          for (var h = 1; h < 24; h++)
                            Positioned(
                              top: h * _hourH - 7,
                              right: 6,
                              child: Text(
                                h == 12 ? '12 pm' : (h < 12 ? '$h am' : '${h - 12} pm'),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                    for (final d in days) _dayColumn(context, s, d, colW, grid, scheme, now),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _dayColumn(BuildContext context, Store s, DateTime d, double colW, Color grid, ColorScheme scheme, DateTime now) {
    final key = dayKey(d);
    final items = s.list('items').where((i) {
      final w = i['when'] as int?;
      return w != null && i['status'] != 'cancelled' && i['allDay'] != true && dayKey(fromMs(w)) == key;
    }).toList()
      ..sort(_byWhen);
    final lanes = _lanes(items);
    final isToday = key == dayKey(now);

    return SizedBox(
      width: colW,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (e) {
          // Snap to the half hour that was tapped.
          final halfHours = (e.localPosition.dy / (_hourH / 2)).floor().clamp(0, 47);
          showTaskSheet(
            context,
            s,
            day: d,
            at: TimeOfDay(hour: halfHours ~/ 2, minute: (halfHours % 2) * 30),
            newKind: 'event',
            presetMinutes: 60,
          );
        },
        child: Stack(
          children: [
            for (var h = 0; h < 24; h++)
              Positioned(
                top: h * _hourH,
                left: 0,
                right: 0,
                child: Container(
                  height: _hourH,
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: grid), left: BorderSide(color: grid)),
                  ),
                ),
              ),
            for (final it in items)
              Builder(builder: (context) {
                final st = fromMs(it['when'] as int);
                final top = (st.hour * 60 + st.minute) / 60 * _hourH;
                final height = min(max(_minutes(it) / 60 * _hourH, 18.0), _hourH * 24 - top + 18);
                final (lane, n) = lanes[it['id'] as int]!;
                final w = colW / n;
                final c = _color(it, scheme);
                final done = it['status'] == 'done';
                return Positioned(
                  top: top,
                  left: lane * w + 1,
                  width: w - 2,
                  height: height - 1,
                  child: GestureDetector(
                    onTap: () => showTaskSheet(context, s, item: it),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: done ? 0.35 : 0.9),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '${it['kind'] == 'alarm' ? '⏰ ' : ''}${it['title']}',
                        overflow: TextOverflow.clip,
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
                top: (now.hour * 60 + now.minute) / 60 * _hourH - 1,
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                    Expanded(child: Container(height: 2, color: Colors.red)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A week with the hours running left to right: one row per day, scroll sideways through the day.
class TimelineGrid extends StatefulWidget {
  const TimelineGrid({super.key, required this.store, required this.start, required this.onDayTap});
  final Store store;
  final DateTime start;
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
  (Map<int, int>, int) _rows(List<Rec> items) {
    final out = <int, int>{};
    final ends = <int>[];
    for (final it in items) {
      final st = it['when'] as int;
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
    final days = [for (var i = 0; i < 7; i++) DateTime(widget.start.year, widget.start.month, widget.start.day + i)];
    final perDay = [
      for (final d in days)
        (s.list('items').where((i) {
          final w = i['when'] as int?;
          return w != null && i['status'] != 'cancelled' && i['allDay'] != true && dayKey(fromMs(w)) == dayKey(d);
        }).toList()
          ..sort(_byWhen)),
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
          showTaskSheet(context, s,
              day: d,
              at: TimeOfDay(hour: halfHours ~/ 2, minute: (halfHours % 2) * 30),
              newKind: 'event',
              presetMinutes: 60);
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
            for (final it in perDay[k])
              Builder(builder: (context) {
                final st = fromMs(it['when'] as int);
                final left = (st.hour * 60 + st.minute) / 60 * _hourW;
                final done = it['status'] == 'done';
                return Positioned(
                  left: left + 1,
                  top: 4 + rows[it['id'] as int]! * (_barH + 4),
                  width: max(_minutes(it) / 60 * _hourW - 2, 28.0),
                  height: _barH,
                  child: GestureDetector(
                    onTap: () => showTaskSheet(context, s, item: it),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: _WeekGridState._colorOf(it, scheme).withValues(alpha: done ? 0.35 : 0.9),
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
              for (var k = 0; k < 7; k++)
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
                children: [hourLabels(), for (var k = 0; k < 7; k++) dayRow(k)],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
    (1, 'Quick', 'Urgent, less important', Colors.blue),
    (0, 'Later', 'Neither', Colors.teal),
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
