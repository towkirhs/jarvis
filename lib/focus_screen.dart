import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'haptics.dart';
import 'store.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _hm(int minutes) => '${minutes ~/ 60}h ${minutes % 60}m';

String _clock(int seconds) => '${two(seconds ~/ 60)}:${two(seconds % 60)}';

/// Pomodoro and stopwatch. The running session lives in the store, so it survives the app closing.
class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key, required this.store});
  final Store store;

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  Timer? _tick;
  String _mode = 'pomo';
  int? _taskId;

  Store get s => widget.store;

  int get _pomoMin => (s.settings['pomoMin'] as int?) ?? 25;
  int get _breakMin => (s.settings['breakMin'] as int?) ?? 5;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) async {
      final wasBreak = s.focusActive?['break'] == true;
      final running = s.focusActive != null;
      await s.checkFocus();
      if (!mounted) return;
      if (running && s.focusActive == null && !wasBreak) _offerBreak();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _offerBreak() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Pomodoro done.'),
        action: SnackBarAction(
          label: 'Take a $_breakMin min break',
          onPressed: () => s.startFocus(mode: 'pomo', minutes: _breakMin, label: 'Break', isBreak: true),
        ),
      ),
    );
  }

  Future<void> _start() async {
    Haptics.tap();
    final task = s.byId('items', _taskId);
    await s.startFocus(
      mode: _mode,
      minutes: _pomoMin,
      taskId: _taskId,
      label: (task?['title'] as String?) ?? 'Focus',
    );
  }

  Future<void> _settings() async {
    var pomo = _pomoMin;
    var brk = _breakMin;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Pomodoro length'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Expanded(child: Text('Focus')),
                IconButton(onPressed: pomo > 5 ? () => setS(() => pomo -= 5) : null, icon: const Icon(Icons.remove)),
                Text('$pomo min'),
                IconButton(onPressed: pomo < 120 ? () => setS(() => pomo += 5) : null, icon: const Icon(Icons.add)),
              ]),
              Row(children: [
                const Expanded(child: Text('Break')),
                IconButton(onPressed: brk > 1 ? () => setS(() => brk -= 1) : null, icon: const Icon(Icons.remove)),
                Text('$brk min'),
                IconButton(onPressed: brk < 30 ? () => setS(() => brk += 1) : null, icon: const Icon(Icons.add)),
              ]),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () {
                s.settings['pomoMin'] = pomo;
                s.settings['breakMin'] = brk;
                s.save();
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final f = s.focusActive;
    final now = DateTime.now().millisecondsSinceEpoch;
    final scheme = Theme.of(context).colorScheme;
    String big;
    double progress;
    if (f == null) {
      big = _mode == 'pomo' ? _clock(_pomoMin * 60) : '00:00';
      progress = 0;
    } else {
      final elapsed = ((now - (f['start'] as int)) / 1000).floor();
      if (f['mode'] == 'pomo') {
        final total = (f['minutes'] as int) * 60;
        big = _clock((total - elapsed).clamp(0, total));
        progress = (elapsed / total).clamp(0.0, 1.0);
      } else {
        big = _clock(elapsed);
        progress = (elapsed % 3600) / 3600;
      }
    }
    final open = s.list('items').where((i) => i['status'] == 'open').toList();
    if (_taskId != null && open.every((i) => i['id'] != _taskId)) _taskId = null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pomo', label: Text('Pomo')),
                ButtonSegment(value: 'watch', label: Text('Stopwatch')),
              ],
              selected: {f == null ? _mode : f['mode'] as String},
              onSelectionChanged: f == null ? (v) => setState(() => _mode = v.first) : null,
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Statistics',
              icon: const Icon(Icons.pie_chart_outline),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FocusStatsPage(store: s))),
            ),
            IconButton(tooltip: 'Pomodoro length', icon: const Icon(Icons.tune), onPressed: f == null ? _settings : null),
          ],
        ),
        const SizedBox(height: 16),
        if (f == null)
          DropdownButton<int?>(
            isExpanded: true,
            value: _taskId,
            hint: const Text('Focus on a task (optional)'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('No task')),
              for (final i in open)
                DropdownMenuItem<int?>(value: i['id'] as int, child: Text(i['title'] as String, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _taskId = v),
          )
        else
          Center(child: Text(f['label'] as String, style: Theme.of(context).textTheme.titleMedium)),
        const SizedBox(height: 24),
        Center(
          child: SizedBox(
            width: 260,
            height: 260,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
                Center(child: Text(big, style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w300))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        Center(
          child: f == null
              ? FilledButton(onPressed: _start, child: const Padding(padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12), child: Text('Start')))
              : OutlinedButton(
                  onPressed: () => s.stopFocus(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                    child: Text(f['mode'] == 'pomo' ? 'Stop' : 'Finish'),
                  ),
                ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Today: ${_todayStats(s).$1} pomos, ${_hm(_todayStats(s).$2)} focused',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// (pomos, minutes) on the given day.
(int, int) _dayStats(Store s, DateTime day) {
  final key = dayKey(day);
  var pomos = 0;
  var minutes = 0;
  for (final f in s.list('focus')) {
    if (dayKey(fromMs(f['start'] as int)) != key) continue;
    if (f['pomo'] == true) pomos++;
    minutes += f['minutes'] as int;
  }
  return (pomos, minutes);
}

(int, int) _todayStats(Store s) => _dayStats(s, DateTime.now());

class FocusStatsPage extends StatelessWidget {
  const FocusStatsPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    final s = store;
    final now = DateTime.now();
    final today = _dayStats(s, now);
    final yesterday = _dayStats(s, DateTime(now.year, now.month, now.day - 1));
    final sessions = s.list('focus');
    final totalPomo = sessions.where((f) => f['pomo'] == true).length;
    final totalMin = sessions.fold<int>(0, (a, f) => a + (f['minutes'] as int));
    final color = Theme.of(context).colorScheme.primary;

    Widget tile(String title, String value, String sub) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (sub.isNotEmpty) Text(sub, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Text(value, style: TextStyle(fontSize: 28, color: color)),
                ],
              ),
            ),
          ),
        );

    Widget section(String title, Widget child) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                child,
              ],
            ),
          ),
        );

    final ranking = <String, int>{};
    for (final f in sessions) {
      ranking.update(f['label'] as String, (v) => v + (f['minutes'] as int), ifAbsent: () => f['minutes'] as int);
    }
    final ranked = ranking.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: const Text('Focus statistics')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(children: [
            tile("Today's pomo", '${today.$1}', '${today.$1 - yesterday.$1 >= 0 ? '+' : ''}${today.$1 - yesterday.$1} from yesterday'),
            tile("Today's focus", _hm(today.$2), '${_hm((today.$2 - yesterday.$2).abs())} ${today.$2 >= yesterday.$2 ? 'more' : 'less'} than yesterday'),
          ]),
          Row(children: [
            tile('Total pomo', '$totalPomo', ''),
            tile('Total focus', _hm(totalMin), ''),
          ]),
          _Trends(store: s, color: color),
          _Timeline(store: s, color: color),
          _MostFocused(store: s, color: color),
          section('Year grid ${now.year}', _YearGrid(store: s, color: color)),
          section(
            'Focus ranking',
            ranked.isEmpty
                ? const Text('No focus sessions yet.')
                : Column(
                    children: [
                      for (final e in ranked.take(8))
                        Row(children: [Expanded(child: Text(e.key, overflow: TextOverflow.ellipsis)), Text(_hm(e.value))]),
                    ],
                  ),
          ),
          section(
            'Focus record',
            sessions.isEmpty
                ? const Text('Nothing recorded yet.')
                : Column(
                    children: [
                      for (final f in sessions.reversed.take(15))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(f['pomo'] == true ? Icons.timer : Icons.av_timer),
                          title: Text(f['label'] as String),
                          subtitle: Text('${dayKey(fromMs(f['start'] as int))}  ${clock(f['start'] as int)} - ${clock(f['end'] as int)}'),
                          trailing: Text('${f['minutes']} min'),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// A card with a title and a "‹ label ›" switcher.
class _NavCard extends StatelessWidget {
  const _NavCard({required this.title, required this.label, required this.onPrev, required this.onNext, required this.child});
  final String title;
  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrev),
                Text(label),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: onNext),
              ]),
              child,
            ],
          ),
        ),
      );
}

int _minutesBetween(Store s, DateTime from, DateTime to) => s
    .list('focus')
    .where((f) {
      final st = fromMs(f['start'] as int);
      return !st.isBefore(from) && st.isBefore(to);
    })
    .fold<int>(0, (a, f) => a + (f['minutes'] as int));

/// Focus per day (week or month view) or per month (year view), with the daily average.
class _Trends extends StatefulWidget {
  const _Trends({required this.store, required this.color});
  final Store store;
  final Color color;

  @override
  State<_Trends> createState() => _TrendsState();
}

class _TrendsState extends State<_Trends> {
  String _mode = 'week';
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    late DateTime start;
    late DateTime end;
    late String label;
    final bars = <(String, int)>[];
    if (_mode == 'week') {
      final monday = s.mondayOf(today);
      start = DateTime(monday.year, monday.month, monday.day + 7 * _offset);
      end = DateTime(start.year, start.month, start.day + 7);
      label = _offset == 0 ? 'This week' : (_offset == -1 ? 'Last week' : '${start.day} ${_months[start.month - 1]}');
      for (var i = 0; i < 7; i++) {
        final d = DateTime(start.year, start.month, start.day + i);
        bars.add((_weekdays[i].substring(0, 2), _minutesBetween(s, d, DateTime(d.year, d.month, d.day + 1))));
      }
    } else if (_mode == 'month') {
      start = DateTime(now.year, now.month + _offset);
      end = DateTime(start.year, start.month + 1);
      label = '${_months[start.month - 1]} ${start.year}';
      for (var d = start; d.isBefore(end); d = DateTime(d.year, d.month, d.day + 1)) {
        bars.add((d.day % 5 == 1 ? '${d.day}' : '', _minutesBetween(s, d, DateTime(d.year, d.month, d.day + 1))));
      }
    } else {
      start = DateTime(now.year + _offset);
      end = DateTime(start.year + 1);
      label = '${start.year}';
      for (var m = 0; m < 12; m++) {
        final a = DateTime(start.year, m + 1);
        bars.add((_months[m].substring(0, 1), _minutesBetween(s, a, DateTime(a.year, a.month + 1))));
      }
    }
    final total = bars.fold<int>(0, (a, b) => a + b.$2);
    final lastDay = end.isAfter(today) ? DateTime(today.year, today.month, today.day + 1) : end;
    final days = max(1, lastDay.difference(start).inDays);
    final top = bars.fold<int>(1, (a, b) => max(a, b.$2));
    return _NavCard(
      title: 'Trends',
      label: label,
      onPrev: () => setState(() => _offset--),
      onNext: _offset < 0 ? () => setState(() => _offset++) : null,
      child: Column(
        children: [
          Center(
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'week', label: Text('Week')),
                ButtonSegment(value: 'month', label: Text('Month')),
                ButtonSegment(value: 'year', label: Text('Year')),
              ],
              selected: {_mode},
              onSelectionChanged: (v) => setState(() {
                _mode = v.first;
                _offset = 0;
              }),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 130,
            child: total == 0
                ? const Center(child: Text('No data'))
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final (name, m) in bars)
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                height: 100 * m / top,
                                color: widget.color,
                              ),
                              Text(name, style: const TextStyle(fontSize: 10)),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Daily average'),
            const Spacer(),
            Text(_hm((total / days).round()), style: const TextStyle(fontSize: 18)),
          ]),
          Row(children: [const Text('Total'), const Spacer(), Text(_hm(total))]),
        ],
      ),
    );
  }
}

class _Timeline extends StatefulWidget {
  const _Timeline({required this.store, required this.color});
  final Store store;
  final Color color;

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final m = s.mondayOf(DateTime.now());
    final start = DateTime(m.year, m.month, m.day + 7 * _offset);
    final end = DateTime(start.year, start.month, start.day + 7);
    final sessions = s.list('focus').where((f) {
      final st = fromMs(f['start'] as int);
      return !st.isBefore(start) && st.isBefore(end);
    }).toList();
    return _NavCard(
      title: 'Timeline',
      label: _offset == 0 ? 'This week' : (_offset == -1 ? 'Last week' : '${start.day} ${_months[start.month - 1]}'),
      onPrev: () => setState(() => _offset--),
      onNext: _offset < 0 ? () => setState(() => _offset++) : null,
      child: SizedBox(
        height: 220,
        child: CustomPaint(painter: _TimelinePainter(sessions, widget.color), size: Size.infinite),
      ),
    );
  }
}

class _MostFocused extends StatefulWidget {
  const _MostFocused({required this.store, required this.color});
  final Store store;
  final Color color;

  @override
  State<_MostFocused> createState() => _MostFocusedState();
}

class _MostFocusedState extends State<_MostFocused> {
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month = DateTime(now.year, now.month + _offset);
    // Minutes focused in each hour of the day, in the chosen month.
    final byHour = List.filled(24, 0);
    for (final f in widget.store.list('focus')) {
      final st = fromMs(f['start'] as int);
      if (st.year != month.year || st.month != month.month) continue;
      for (var t = f['start'] as int; t < (f['end'] as int); t += 60000) {
        byHour[fromMs(t).hour]++;
      }
    }
    final top = byHour.fold<int>(1, (a, b) => max(a, b));
    return _NavCard(
      title: 'Most focused time',
      label: '${_months[month.month - 1]} ${month.year}',
      onPrev: () => setState(() => _offset--),
      onNext: _offset < 0 ? () => setState(() => _offset++) : null,
      child: Column(
        children: [
          SizedBox(
            height: 100,
            child: byHour.every((m) => m == 0)
                ? const Center(child: Text('No data'))
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var hr = 0; hr < 24; hr++)
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            height: 100 * byHour[hr] / top,
                            color: widget.color,
                          ),
                        ),
                    ],
                  ),
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text('00:00'), Text('06:00'), Text('12:00'), Text('18:00'), Text('24:00')],
          ),
        ],
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.sessions, this.color);
  final List<Rec> sessions;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 36.0;
    const bottom = 16.0;
    final h = size.height - bottom;
    final colW = (size.width - left) / 7;
    final grid = Paint()..color = Colors.grey.withValues(alpha: 0.3);
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final hour in [0, 6, 12, 18, 24]) {
      final y = h * hour / 24;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      if (hour < 24) {
        tp.text = TextSpan(text: '${two(hour)}:00', style: const TextStyle(fontSize: 9, color: Colors.grey));
        tp.layout();
        tp.paint(canvas, Offset(0, y));
      }
    }
    for (var d = 0; d < 7; d++) {
      tp.text = TextSpan(text: _weekdays[d], style: const TextStyle(fontSize: 9, color: Colors.grey));
      tp.layout();
      tp.paint(canvas, Offset(left + colW * d + (colW - tp.width) / 2, h + 2));
    }
    final bar = Paint()..color = color;
    for (final f in sessions) {
      final st = fromMs(f['start'] as int);
      final en = fromMs(f['end'] as int);
      final x = left + colW * (st.weekday - 1);
      final y1 = h * (st.hour * 60 + st.minute) / 1440;
      final y2 = h * (en.hour * 60 + en.minute) / 1440;
      canvas.drawRect(Rect.fromLTRB(x + 2, y1, x + colW - 2, (y2 - y1) < 2 ? y1 + 2 : y2), bar);
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) => true;
}

class _YearGrid extends StatelessWidget {
  const _YearGrid({required this.store, required this.color});
  final Store store;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final perDay = <String, int>{};
    for (final f in store.list('focus')) {
      final k = dayKey(fromMs(f['start'] as int));
      perDay[k] = (perDay[k] ?? 0) + (f['minutes'] as int);
    }
    Color shade(int m) {
      if (m == 0) return Colors.grey.withValues(alpha: 0.2);
      if (m < 60) return color.withValues(alpha: 0.3);
      if (m < 180) return color.withValues(alpha: 0.55);
      if (m < 300) return color.withValues(alpha: 0.8);
      return color;
    }

    final first = store.mondayOf(DateTime(now.year, 1, 1));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var w = 0; w < 53; w++)
                Column(
                  children: [
                    for (var d = 0; d < 7; d++)
                      Builder(builder: (_) {
                        final day = DateTime(first.year, first.month, first.day + w * 7 + d);
                        return Container(
                          width: 11,
                          height: 11,
                          margin: const EdgeInsets.all(1),
                          color: day.year == now.year && !day.isAfter(now)
                              ? shade(perDay[dayKey(day)] ?? 0)
                              : Colors.transparent,
                        );
                      }),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: [
            for (final (m, label) in [(0, '0m'), (30, '0-1h'), (120, '1-3h'), (240, '3-5h'), (400, '>5h')])
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, color: shade(m)),
                const SizedBox(width: 4),
                Text(label, style: const TextStyle(fontSize: 11)),
              ]),
          ],
        ),
      ],
    );
  }
}
