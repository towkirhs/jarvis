import 'package:flutter/material.dart';

import 'habit_stats.dart';
import 'store.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Creates a habit, or edits [habit] when given. Returns the habit, or null if cancelled.
Future<Rec?> showAddHabit(BuildContext context, Store store, {String name = '', Rec? habit}) {
  final nameCtrl = TextEditingController(text: (habit?['name'] as String?) ?? name);
  var times = (habit?['times'] as int?) ?? 3;
  var per = (habit?['per'] as String?) ?? 'week';
  var remind = habit?['remind'] as String?;
  var color = (habit?['color'] as int?) ?? store.list('habits').length;
  return showDialog<Rec>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final maxTimes = per == 'week' ? 7 : 31;
        if (times > maxTimes) times = maxTimes;
        return AlertDialog(
          title: Text(habit == null ? 'New habit' : 'Edit habit'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name, like gym')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      onPressed: times > 1 ? () => setS(() => times--) : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Text('$times'),
                    IconButton(
                      onPressed: times < maxTimes ? () => setS(() => times++) : null,
                      icon: const Icon(Icons.add),
                    ),
                    const Text('times per '),
                    DropdownButton<String>(
                      value: per,
                      items: const [
                        DropdownMenuItem(value: 'week', child: Text('week')),
                        DropdownMenuItem(value: 'month', child: Text('month')),
                      ],
                      onChanged: (v) => setS(() => per = v ?? per),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Daily reminder'),
                  subtitle: remind == null ? null : Text(remind!),
                  value: remind != null,
                  onChanged: (on) async {
                    if (!on) {
                      setS(() => remind = null);
                      return;
                    }
                    final t = await showTimePicker(context: ctx, initialTime: const TimeOfDay(hour: 20, minute: 0));
                    if (t != null) setS(() => remind = '${two(t.hour)}:${two(t.minute)}');
                  },
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < habitColors.length; i++)
                      GestureDetector(
                        onTap: () => setS(() => color = i),
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: Color(habitColors[i]),
                          child: color % habitColors.length == i
                              ? const Icon(Icons.check, size: 16, color: Colors.black)
                              : null,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final n = nameCtrl.text.trim();
                if (n.isEmpty) return;
                if (habit == null) {
                  final h = await store.addHabit(n, times, per: per, remind: remind);
                  h['color'] = color;
                  store.save();
                  if (ctx.mounted) Navigator.pop(ctx, h);
                  return;
                }
                await store.updateRec('habits', habit, 'Edited habit $n', (r) {
                  r['name'] = n;
                  r['times'] = times;
                  r['per'] = per;
                  r['color'] = color;
                  r['remind'] = remind;
                  if (remind != null) r['rid'] ??= store.nextId();
                });
                if (ctx.mounted) Navigator.pop(ctx, habit);
              },
              child: Text(habit == null ? 'Add' : 'Save'),
            ),
          ],
        );
      },
    ),
  );
}

/// Cycles a day: blank -> done -> skipped -> blank. Blank means "not said", which never counts as a miss.
void _cycle(Store store, Rec h, String day) {
  final v = (h['logs'] as Rec)[day];
  store.logHabit(h, day, v == null ? 'yes' : (v == 'yes' ? 'no' : null));
}

Widget _dayMark(Rec h, String day) {
  final v = (h['logs'] as Rec)[day];
  if (v == 'yes') return Icon(Icons.check, color: Color(habitColor(h)));
  if (v == 'no') return const Icon(Icons.close, color: Colors.grey);
  return const Icon(Icons.circle, size: 6, color: Colors.grey);
}

class HabitsScreen extends StatelessWidget {
  const HabitsScreen({super.key, required this.store});
  final Store store;

  static const _cell = 44.0;

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () => showAddHabit(context, store),
          child: const Icon(Icons.add),
        ),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final now = DateTime.now();
            final days = [for (var i = 0; i < 5; i++) DateTime(now.year, now.month, now.day - i)];
            final habits = store.list('habits');
            final small = Theme.of(context).textTheme.labelSmall;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Habits', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                const Text('Tap a day: done, skipped, blank. Or just tell Jarvis, like "went to the gym today".'),
                const SizedBox(height: 12),
                if (habits.isEmpty)
                  const Text('No habits yet. Add one, or say "I want to read 3 times a week".')
                else
                  Row(
                    children: [
                      const Spacer(),
                      for (final d in days)
                        SizedBox(
                          width: _cell,
                          child: Column(
                            children: [
                              Text(_weekdays[d.weekday - 1].toUpperCase(), style: small),
                              Text('${d.day}', style: small),
                            ],
                          ),
                        ),
                    ],
                  ),
                for (final h in habits)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => HabitPage(store: store, id: h['id'] as int)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        value: habitScore(h, now),
                                        strokeWidth: 3,
                                        color: Color(habitColor(h)),
                                        backgroundColor: Colors.grey.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        h['name'] as String,
                                        style: TextStyle(color: Color(habitColor(h)), fontSize: 16),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          for (final d in days)
                            SizedBox(
                              width: _cell,
                              height: _cell,
                              child: InkWell(
                                onTap: () => _cycle(store, h, dayKey(d)),
                                child: Center(child: _dayMark(h, dayKey(d))),
                              ),
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
          return Scaffold(
            appBar: AppBar(
              title: Text(h['name'] as String),
              actions: [
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit),
                  onPressed: () => showAddHabit(context, store, habit: h),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    store.removeRec('habits', h, 'Deleted habit ${h['name']}');
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '${habitTarget(h)}${h['remind'] == null ? '' : '   ·   reminder ${h['remind']}'}'
                    '   ·   streak ${store.streakPeriods(h)} ${h['per']}s',
                  ),
                ),
                _section('Overview', color, _overview(h, color, now)),
                _section('Score', color, _scoreChart(h, color)),
                _section('History', color, _history(h, color)),
                _section('Calendar', color, _calendar(context, h, color, now)),
                _section('Best streaks', color, _streaks(h, color)),
                _section('Frequency', color, _frequency(h, color)),
              ],
            ),
          );
        },
      );

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
    final logs = h['logs'] as Rec;
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
                      final key = dayKey(day);
                      final v = logs[key];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: InkWell(
                          onTap: () => _cycle(store, h, key),
                          child: Container(
                            width: size,
                            height: size,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: v == 'yes' ? color : Colors.grey.withValues(alpha: v == 'no' ? 0.35 : 0.15),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              '${day.day}',
                              style: TextStyle(fontSize: 12, color: v == 'yes' ? Colors.black : null),
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
