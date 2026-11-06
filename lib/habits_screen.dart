import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'habit_core.dart';
import 'habit_editor.dart';
import 'habit_stats.dart';
import 'habit_widgets.dart';
import 'haptics.dart';
import 'store.dart';

export 'habit_editor.dart' show showAddHabit;
export 'habit_widgets.dart' show HabitTodayRow;

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

void _openHabit(BuildContext context, Store store, Rec h) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => HabitPage(store: store, id: h['id'] as int)));

/// Quick back-filling of a past day: yes/no habits cycle done, missed, rest day, blank; measured ones open the day.
void _tapDay(BuildContext context, Store store, Rec h, DateTime day) {
  final type = (h['type'] as String?) ?? 'yesno';
  if (type != 'yesno') {
    showHabitDay(context, store, h, day);
    return;
  }
  final key = dk(day);
  final e = HabitCore.entry(h, key);
  final next = e == null
      ? 'yes'
      : HabitCore.done(h, day)
          ? 'no'
          : e['miss'] == true
              ? 'skip'
              : null;
  next == 'yes' ? Haptics.success() : Haptics.tick();
  store.logHabit(h, key, next);
}

Widget _dayMark(BuildContext context, Rec h, DateTime day) {
  final color = Color(habitColor(h));
  if (!HabitCore.scheduled(h, day)) return Icon(Icons.remove, size: 14, color: Colors.grey.withValues(alpha: 0.4));
  final e = HabitCore.entry(h, dk(day));
  if (e?['skip'] == true) return const Icon(Icons.bedtime_outlined, size: 18, color: Colors.grey);
  if (e?['miss'] == true) return const Icon(Icons.close, color: Colors.grey);
  final p = HabitCore.progress(h, day);
  if (p == null) return const Icon(Icons.circle, size: 6, color: Colors.grey);
  if (p >= 1) return Icon(Icons.check, color: color);
  return SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(value: p, strokeWidth: 3, color: color, backgroundColor: color.withValues(alpha: 0.2)),
  );
}

String _routineName(String? r) => switch (r) {
      null || '' => 'Anytime',
      'morning' => 'Morning routine',
      'evening' => 'Evening routine',
      _ => r,
    };

class HabitsScreen extends StatelessWidget {
  const HabitsScreen({super.key, required this.store});
  final Store store;

  static const _cell = 40.0;

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton(
          tooltip: 'New habit',
          onPressed: () => showAddHabit(context, store),
          child: const Icon(Icons.add),
        ),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final now = DateTime.now();
            final scheme = Theme.of(context).colorScheme;
            final tt = Theme.of(context).textTheme;
            final habits = store.orderedHabits();
            final archived = store.orderedHabits(archived: true);
            final today = habits.where((h) => HabitCore.onToday(h, now)).toList();
            final doneToday = today.where((h) => HabitCore.done(h, now)).length;
            final dayP = HabitCore.dayProgress(habits, now);
            final days = [for (var i = 4; i >= 0; i--) DateTime(now.year, now.month, now.day - i)];
            final small = tt.labelSmall;
            // Group today's habits by routine, keeping the routine order.
            final groups = <String, List<Rec>>{};
            for (final h in habits) {
              groups.putIfAbsent(_routineName(h['routine'] as String?), () => []).add(h);
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Row(children: [
                  Expanded(child: Text('Habits', style: tt.headlineSmall)),
                  IconButton(
                    tooltip: 'Reports',
                    icon: const Icon(Icons.insights_outlined),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HabitReportPage(store: store))),
                  ),
                  if (habits.length > 1)
                    IconButton(
                      tooltip: 'Reorder',
                      icon: const Icon(Icons.swap_vert),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HabitOrderPage(store: store))),
                    ),
                ]),
                if (habits.isEmpty) ...[
                  const SizedBox(height: 24),
                  Text('No habits yet. Add one with +, or tell Jarvis, like "I want to drink 3 litres of water a day".',
                      style: tt.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
                ] else ...[
                  if (dayP != null) ...[
                    const SizedBox(height: 8),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${(dayP * 100).round()}%', style: tt.displaySmall),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('of today, $doneToday of ${today.length} done', style: tt.bodyMedium),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(value: dayP, minHeight: 10, backgroundColor: scheme.surfaceContainerHighest),
                    ),
                    const SizedBox(height: 16),
                    _WeekStrip(habits: habits, now: now),
                  ],
                  for (final g in groups.entries)
                    if (g.value.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
                        child: Text(g.key, style: tt.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Column(children: [
                            for (final h in g.value)
                              HabitTodayRow(store: store, habit: h, flat: true, onOpen: () => _openHabit(context, store, h)),
                          ]),
                        ),
                      ),
                    ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 24, 4, 6),
                    child: Text('Last 5 days', style: tt.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(children: [
                        Row(children: [
                          const Spacer(),
                          for (final d in days)
                            SizedBox(
                              width: _cell,
                              child: Column(children: [
                                Text(_weekdays[d.weekday - 1], style: small),
                                Text('${d.day}', style: small),
                              ]),
                            ),
                          const SizedBox(width: 8),
                        ]),
                        for (final h in habits)
                          Row(children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => _openHabit(context, store, h),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                                  child: Text(h['name'] as String,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: Color(habitColor(h)), fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ),
                            for (final d in days)
                              SizedBox(
                                width: _cell,
                                height: _cell,
                                child: InkWell(
                                  onTap: HabitCore.scheduled(h, d) ? () => _tapDay(context, store, h, d) : null,
                                  onLongPress: () => showHabitDay(context, store, h, d),
                                  child: Center(child: _dayMark(context, h, d)),
                                ),
                              ),
                            const SizedBox(width: 8),
                          ]),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                          child: Text('Tap a day: done, missed, rest day, blank. Hold for notes and amounts.', style: small),
                        ),
                      ]),
                    ),
                  ),
                ],
                if (archived.isNotEmpty)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: const Icon(Icons.archive_outlined),
                    title: Text('Archived (${archived.length})'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ArchivedHabitsPage(store: store))),
                  ),
              ],
            );
          },
        ),
      );
}

/// This week, one dot per day: how much of that day's habits got done.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.habits, required this.now});
  final List<Rec> habits;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    return Row(children: [
      for (var i = 0; i < 7; i++)
        Expanded(
          child: Builder(builder: (context) {
            final d = DateTime(monday.year, monday.month, monday.day + i);
            final future = d.isAfter(now);
            final on = habits.where((h) => HabitCore.scheduled(h, d) && !HabitCore.skipped(h, d)).toList();
            final p = future || on.isEmpty ? null : on.fold<double>(0, (a, h) => a + (HabitCore.progress(h, d) ?? 0)) / on.length;
            final isToday = dk(d) == dk(now);
            return Column(children: [
              Text(_weekdays[i].substring(0, 1),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: isToday ? FontWeight.w800 : null)),
              const SizedBox(height: 4),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  value: p ?? 0,
                  strokeWidth: 4,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ]);
          }),
        ),
    ]);
  }
}

/// Drag habits into the order you do them.
class HabitOrderPage extends StatelessWidget {
  const HabitOrderPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Order')),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final habits = store.orderedHabits();
            return ReorderableListView(
              padding: const EdgeInsets.all(12),
              onReorder: (from, to) {
                if (to > from) to--;
                final moved = habits.removeAt(from);
                habits.insert(to, moved);
                for (var i = 0; i < habits.length; i++) {
                  habits[i]['order'] = i;
                }
                // Moving next to another routine's habits joins that routine.
                final neighbour = habits.length > 1 ? habits[to == 0 ? 1 : to - 1] : null;
                if (neighbour != null && neighbour['routine'] != moved['routine']) moved['routine'] = neighbour['routine'];
                Haptics.tick();
                store.save();
              },
              children: [
                for (final h in habits)
                  ListTile(
                    key: ValueKey(h['id']),
                    leading: Icon(habitIcon(h), color: Color(habitColor(h))),
                    title: Text(h['name'] as String),
                    subtitle: Text(_routineName(h['routine'] as String?)),
                    trailing: const Icon(Icons.drag_handle),
                  ),
              ],
            );
          },
        ),
      );
}

class ArchivedHabitsPage extends StatelessWidget {
  const ArchivedHabitsPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Archived habits')),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final h in store.orderedHabits(archived: true))
                Card(
                  child: ListTile(
                    leading: Icon(habitIcon(h), color: Color(habitColor(h))),
                    title: Text(h['name'] as String),
                    subtitle: Text('${HabitCore.totalDone(h)} days done, best streak ${HabitCore.longestStreak(h, DateTime.now())}'),
                    trailing: TextButton(
                      onPressed: () => store.updateRec('habits', h, 'Restored habit ${h['name']}', (r) => r['archived'] = false),
                      child: const Text('Restore'),
                    ),
                    onTap: () => _openHabit(context, store, h),
                  ),
                ),
            ],
          ),
        ),
      );
}

/// Weekly, monthly and yearly report across all habits.
class HabitReportPage extends StatefulWidget {
  const HabitReportPage({super.key, required this.store});
  final Store store;

  @override
  State<HabitReportPage> createState() => _HabitReportPageState();
}

class _HabitReportPageState extends State<HabitReportPage> {
  String _range = 'week';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = switch (_range) {
      'month' => DateTime(now.year, now.month),
      'year' => DateTime(now.year),
      _ => DateTime(now.year, now.month, now.day - (now.weekday - 1)),
    };
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final habits = widget.store.orderedHabits();
    final rates = [for (final h in habits) HabitCore.rate(h, from, today)];
    final known = rates.whereType<double>().toList();
    final overall = known.isEmpty ? null : known.reduce((a, b) => a + b) / known.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Habit report')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'week', label: Text('This week')),
              ButtonSegment(value: 'month', label: Text('This month')),
              ButtonSegment(value: 'year', label: Text('This year')),
            ],
            selected: {_range},
            onSelectionChanged: (v) => setState(() => _range = v.first),
          ),
          const SizedBox(height: 16),
          Text(overall == null ? 'Nothing to report yet' : '${(overall * 100).round()}% done', style: tt.headlineMedium),
          Text('Of the days your habits were due, rest days left out.', style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          for (var i = 0; i < habits.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(habitIcon(habits[i]), size: 18, color: Color(habitColor(habits[i]))),
                    const SizedBox(width: 8),
                    Expanded(child: Text(habits[i]['name'] as String, style: tt.titleSmall)),
                    Text(rates[i] == null ? '–' : '${(rates[i]! * 100).round()}%', style: tt.titleSmall),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: rates[i] ?? 0,
                      minHeight: 6,
                      color: Color(habitColor(habits[i])),
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      '${HabitCore.slots(habits[i], today, from: from).where((s) => s.$2 == Slot.done).length} done',
                      '${HabitCore.missedCount(habits[i], today, from: from)} missed',
                      if (!const ['yesno', 'time', 'checklist', 'rating'].contains(habits[i]['type'] ?? 'yesno'))
                        'total ${fmtNum(HabitCore.totalValue(habits[i], from, today))} ${habits[i]['type'] == 'duration' ? 'min' : (habits[i]['unit'] ?? '')}'.trim(),
                    ].join(', '),
                    style: tt.bodySmall,
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class HabitPage extends StatelessWidget {
  const HabitPage({super.key, required this.store, required this.id});
  final Store store;
  final int id;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final h = store.byId('habits', id);
          if (h == null) return const Scaffold(body: Center(child: Text('Habit deleted.')));
          final color = Color(habitColor(h));
          final now = DateTime.now();
          final paused = HabitCore.isPaused(h, now);
          final archived = h['archived'] == true;
          final tt = Theme.of(context).textTheme;
          final (reached, nextMilestone) = HabitCore.milestonesOf(h);
          final notes = [
            for (final e in (h['logs'] as Rec).entries)
              if (e.value is Map && ((e.value as Map)['note'] != null || (e.value as Map)['photo'] != null)) e,
          ]..sort((a, b) => (b.key).compareTo(a.key));
          final t = HabitCore.target(h, now);
          return Scaffold(
            appBar: AppBar(
              title: Text(h['name'] as String),
              actions: [
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => showAddHabit(context, store, habit: h),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    final today = dk(now);
                    switch (v) {
                      case 'pause':
                        await store.updateRec('habits', h, 'Paused ${h['name']}', (r) {
                          r['off'] = [...((r['off'] as List?) ?? []), [today, null]];
                        });
                      case 'resume':
                        await store.updateRec('habits', h, 'Resumed ${h['name']}', (r) {
                          final off = ((r['off'] as List?) ?? []).map((x) => List.of(x as List)).toList();
                          for (final range in off) {
                            if (range[1] == null) {
                              range[1] = dk(DateTime(now.year, now.month, now.day - 1));
                            }
                          }
                          // A pause that started today and ended yesterday is no pause at all.
                          r['off'] = off.where((x) => (x[1] as String).compareTo(x[0] as String) >= 0).toList();
                        });
                      case 'archive':
                        await store.updateRec('habits', h, 'Archived ${h['name']}', (r) => r['archived'] = !archived);
                      case 'delete':
                        Haptics.warn();
                        store.removeRec('habits', h, 'Deleted habit ${h['name']}');
                        if (context.mounted) Navigator.pop(context);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: paused ? 'resume' : 'pause', child: Text(paused ? 'Resume' : 'Pause')),
                    PopupMenuItem(value: 'archive', child: Text(archived ? 'Restore from archive' : 'Archive')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                  child: Text(
                    [
                      HabitType.of(h).label,
                      if (t != null && !const ['yesno', 'time', 'checklist'].contains(h['type'] ?? 'yesno'))
                        '${h['type'] == 'limit' ? 'at most ' : ''}${fmtNum(t)} ${h['type'] == 'duration' ? 'min' : (h['unit'] ?? '')}'.trim(),
                      if (h['by'] != null) 'by ${time12(h['by'] as String)}',
                      HabitCore.describe(h).toLowerCase(),
                      if (h['goal'] != null) goals[h['goal']]!.toLowerCase(),
                      if (h['remind'] != null) 'reminder ${time12(h['remind'] as String)}',
                      if (paused) 'paused',
                      if (archived) 'archived',
                    ].join(', '),
                    style: tt.bodyMedium,
                  ),
                ),
                if (!archived && HabitCore.scheduled(h, now))
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: HabitTodayRow(store: store, habit: h, flat: true),
                    ),
                  ),
                _section('Streaks', color, Row(children: [
                  _bigStat(context, '${HabitCore.currentStreak(h, now)}', 'current (${HabitCore.unit(h)}s)', color),
                  _bigStat(context, '${HabitCore.longestStreak(h, now)}', 'longest', color),
                  _bigStat(context, '${HabitCore.consistency(h, now)}%', 'consistency', color),
                  _bigStat(context, '${HabitCore.missedCount(h, now, from: DateTime(now.year, now.month, now.day - 29))}', 'missed, 30 days', color),
                ])),
                _section('Milestones', color, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final m in HabitCore.milestones.take(reached.length + 2))
                      Chip(
                        avatar: Icon(reached.contains(m) ? Icons.emoji_events : Icons.lock_outline,
                            size: 18, color: reached.contains(m) ? color : null),
                        label: Text('$m ${m == 1 ? 'day' : 'days'}'),
                      ),
                  ]),
                  if (nextMilestone != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('${nextMilestone - HabitCore.totalDone(h)} more to $nextMilestone days.'),
                    ),
                ])),
                _section('Year', color, _heatmap(context, h, color, now)),
                _section('Overview', color, _overview(h, color, now)),
                _section('Score', color, _scoreChart(h, color)),
                _section('History', color, _history(h, color)),
                _section('Calendar', color, _calendar(context, h, color, now)),
                _section('Best streaks', color, _streaks(h, color)),
                _section('Frequency', color, _frequency(h, color)),
                if (notes.isNotEmpty)
                  _section('Notes and photos', color, Column(children: [
                    for (final e in notes.take(30))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: (e.value as Map)['photo'] != null && !kIsWeb
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.file(File((e.value as Map)['photo'] as String), width: 48, height: 48, fit: BoxFit.cover),
                              )
                            : const Icon(Icons.notes),
                        title: Text(((e.value as Map)['note'] as String?) ?? 'Photo'),
                        subtitle: Text(_shortDate(DateTime.parse(e.key))),
                        onTap: () => showHabitDay(context, store, h, DateTime.parse(e.key)),
                      ),
                  ])),
              ],
            ),
          );
        },
      );

  Widget _bigStat(BuildContext context, String value, String label, Color color) => Expanded(
        child: Column(children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color)),
          Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );

  /// The last year, one square per day, darker for more done; GitHub-style.
  Widget _heatmap(BuildContext context, Rec h, Color color, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final first = store.mondayOf(today).subtract(const Duration(days: 7 * 52));
    final empty = Theme.of(context).colorScheme.surfaceContainerHighest;
    const size = 11.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var w = 0; w < 53; w++)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Column(children: [
              for (var d = 0; d < 7; d++)
                Builder(builder: (_) {
                  final day = DateTime(first.year, first.month, first.day + 7 * w + d);
                  if (day.isAfter(today)) return const SizedBox(width: size, height: size + 2);
                  final p = HabitCore.progress(h, day);
                  final skip = HabitCore.skipped(h, day);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: skip
                            ? Colors.grey.withValues(alpha: 0.35)
                            : (p == null || p == 0 ? empty : Color.lerp(color.withValues(alpha: 0.25), color, p)),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
            ]),
          ),
      ]),
    );
  }

  Widget _section(String title, Color color, Widget child) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: color, fontSize: 18)),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );

  Widget _overview(Rec h, Color color, DateTime now) {
    final score = habitScore(h, now);
    final month = score - habitScore(h, DateTime(now.year, now.month - 1, now.day));
    final year = score - habitScore(h, DateTime(now.year - 1, now.month, now.day));
    String pct(double v, {bool sign = false}) => '${sign && v >= 0 ? '+' : ''}${(v * 100).round()}%';
    Widget stat(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: TextStyle(color: color, fontSize: 18)),
              Text(label),
            ],
          ),
        );
    return Row(
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            value: score,
            strokeWidth: 5,
            color: color,
            backgroundColor: Colors.grey.withValues(alpha: 0.3),
          ),
        ),
        stat(pct(score), 'Score'),
        stat(pct(month, sign: true), 'Month'),
        stat(pct(year, sign: true), 'Year'),
        stat('${habitTotal(h)}', 'Total'),
      ],
    );
  }

  Widget _scoreChart(Rec h, Color color) {
    final months = lastMonths(6);
    return Column(
      children: [
        SizedBox(
          height: 120,
          width: double.infinity,
          child: CustomPaint(painter: _LinePainter(monthScores(h, 6), color)),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final m in months)
              Expanded(child: Text(_months[m.month - 1], textAlign: TextAlign.center)),
          ],
        ),
      ],
    );
  }

  Widget _history(Rec h, Color color) {
    final months = lastMonths(6);
    final counts = monthCounts(h, 6);
    final top = counts.fold<int>(1, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < months.length; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (counts[i] > 0) Text('${counts[i]}', style: TextStyle(color: color)),
                  Container(
                    width: 18,
                    height: 90 * counts[i] / top,
                    color: color,
                  ),
                  const SizedBox(height: 4),
                  Text(_months[months[i].month - 1]),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The last 20 weeks, one column per week. Tap a day to change it.
  Widget _calendar(BuildContext context, Rec h, Color color, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final first = store.mondayOf(today).subtract(const Duration(days: 7 * 19));
    const size = 30.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var w = 0; w < 20; w++)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Column(
                children: [
                  SizedBox(
                    height: 18,
                    child: Builder(builder: (_) {
                      final monday = DateTime(first.year, first.month, first.day + 7 * w);
                      return monday.day <= 7 ? Text(_months[monday.month - 1]) : const SizedBox();
                    }),
                  ),
                  for (var d = 0; d < 7; d++)
                    Builder(builder: (_) {
                      final day = DateTime(first.year, first.month, first.day + 7 * w + d);
                      if (day.isAfter(today)) return const SizedBox(width: size, height: size + 3);
                      final p = HabitCore.progress(h, day);
                      final done = (p ?? 0) >= 1;
                      final e = HabitCore.entry(h, dk(day));
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: InkWell(
                          onTap: () => _tapDay(context, store, h, day),
                          onLongPress: () => showHabitDay(context, store, h, day),
                          child: Container(
                            width: size,
                            height: size,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: done
                                  ? color
                                  : (p != null && p > 0
                                      ? color.withValues(alpha: 0.2 + 0.5 * p)
                                      : Colors.grey.withValues(alpha: e?['miss'] == true || e?['skip'] == true ? 0.35 : 0.15)),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              e?['skip'] == true ? '–' : '${day.day}',
                              style: TextStyle(fontSize: 12, color: done ? Colors.black : null),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          Column(
            children: [
              const SizedBox(height: 18),
              for (final d in _weekdays)
                SizedBox(height: size + 3, child: Center(child: Text(' $d'))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _streaks(Rec h, Color color) {
    final streaks = bestStreaks(h, 6);
    if (streaks.isEmpty) return const Text('No streaks yet.');
    final top = streaks.map((s) => s.length).reduce((a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final s in streaks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(width: 92, child: Text(_shortDate(s.start), textAlign: TextAlign.right)),
                const SizedBox(width: 8),
                Expanded(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.3 + 0.7 * s.length / top,
                    child: Container(
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: s.length == top ? color : color.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('${s.length}', style: const TextStyle(color: Colors.black)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 92, child: Text(_shortDate(s.end))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _frequency(Rec h, Color color) {
    final counts = weekdayCounts(h);
    final top = counts.fold<int>(1, (a, b) => b > a ? b : a);
    return Column(
      children: [
        for (var i = 0; i < 7; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(width: 40, child: Text(_weekdays[i])),
                Expanded(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: counts[i] / top,
                    child: Container(height: 14, color: color),
                  ),
                ),
                SizedBox(width: 32, child: Text('${counts[i]}', textAlign: TextAlign.right)),
              ],
            ),
          ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.grey.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.isEmpty) return;
    final step = size.width / values.length;
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(step * (i + 0.5), size.height * (1 - values[i])),
    ];
    final line = Paint()
      ..color = color
      ..strokeWidth = 2.5;
    for (var i = 1; i < points.length; i++) {
      canvas.drawLine(points[i - 1], points[i], line);
    }
    final dot = Paint()..color = color;
    for (final p in points) {
      canvas.drawCircle(p, 4, dot);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.values != values || old.color != color;
}
