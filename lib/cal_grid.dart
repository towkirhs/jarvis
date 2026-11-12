import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'cal_edit.dart';
import 'cal_event.dart';
import 'cal_index.dart';
import 'cal_quick.dart';
import 'haptics.dart';
import 'store.dart';
import 'task_sheet.dart';
import 'theme.dart' show accents;

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The colour of an item's block: its own colour, else its priority, else its kind.
Color eventColor(Rec it, ColorScheme scheme) {
  final own = accents[it['color']];
  if (own != null) return own;
  final p = (it['priority'] as int?) ?? 0;
  if (p > 0) return priorityColors[p];
  return switch (it['kind']) {
    'alarm' => Colors.deepOrange,
    'task' => scheme.tertiary,
    _ => scheme.primary,
  };
}

/// Text on top of an event colour.
Color onEventColor(Color c) => c.computeLuminance() > 0.6 ? Colors.black87 : Colors.white;

/// The sums behind the time grid, apart from any drawing so they can be tested.
class GridMath {
  static const hourH = 60.0;
  static const snap = 15;

  static int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

  /// The minute of the day at height [dy], rounded down to a multiple of [step] and kept inside the day.
  static int minuteAt(double dy, {int step = 30}) => _clamp((dy / hourH * 60).floor() ~/ step * step, 0, 24 * 60 - step);

  /// The column at [dx] when each column is [colW] wide.
  static int columnAt(double dx, double colW, int count) => _clamp((dx / colW).floor(), 0, count - 1);

  /// Where a block that starts at [startMin] and runs [dur] minutes starts after being dragged down by [dy].
  static int movedStart(int startMin, double dy, int dur) {
    final m = ((startMin + dy / hourH * 60) / snap).round() * snap;
    return _clamp(m, 0, max(0, 24 * 60 - min(dur, 24 * 60)));
  }

  /// A block's length after its bottom edge is dragged down by [dy].
  static int resized(int dur, double dy, int startMin) {
    final d = ((dur + dy / hourH * 60) / snap).round() * snap;
    return _clamp(d, snap, max(snap, 24 * 60 - startMin));
  }

  /// Lays out overlapping blocks side by side. [spans] are (start, end) minutes sorted by start; returns the
  /// lane of each and how many lanes its cluster of overlapping blocks needs.
  static List<(int, int)> lanes(List<(int, int)> spans) {
    final out = List<(int, int)>.filled(spans.length, (0, 1));
    var i = 0;
    while (i < spans.length) {
      final laneEnds = <int>[];
      final lane = <int>[];
      var clusterEnd = spans[i].$2;
      var j = i;
      while (j < spans.length && (j == i || spans[j].$1 < clusterEnd)) {
        final (st, en) = spans[j];
        var l = laneEnds.indexWhere((e) => e <= st);
        if (l < 0) {
          l = laneEnds.length;
          laneEnds.add(en);
        } else {
          laneEnds[l] = en;
        }
        lane.add(l);
        if (en > clusterEnd) clusterEnd = en;
        j++;
      }
      for (var k = 0; k < lane.length; k++) {
        out[i + k] = (lane[k], laneEnds.length);
      }
      i = j;
    }
    return out;
  }
}

String _hourLabel(int h) => h == 0 ? '12 am' : (h == 12 ? '12 pm' : (h < 12 ? '$h am' : '${h - 12} pm'));

/// Google Calendar style days: swipe sideways for the next days, hours run down, blocks can be dragged to
/// move and pulled at the bottom to resize, and a tap on an empty hour opens a small sheet to add there.
class TimeGrid extends StatefulWidget {
  const TimeGrid({
    super.key,
    required this.store,
    required this.anchor,
    required this.count,
    required this.onVisible,
    required this.onDayTap,
  });
  final Store store;

  /// The first day of the page the grid opens on.
  final DateTime anchor;

  /// How many days one page shows: 1, 2, 3 or 7.
  final int count;

  /// Called with the first day of the page that came into view.
  final void Function(DateTime start) onVisible;
  final void Function(DateTime day) onDayTap;

  @override
  State<TimeGrid> createState() => TimeGridState();
}

class TimeGridState extends State<TimeGrid> {
  static const _home = 5000;
  static const _gutter = 48.0;
  static const _hourH = GridMath.hourH;
  late final PageController _body = PageController(initialPage: _home)..addListener(_follow);
  late final PageController _head = PageController(initialPage: _home);
  late final ScrollController _scroll =
      ScrollController(initialScrollOffset: _hourH * ((DateTime.now().hour - 2).clamp(0, 16)));
  int _page = _home;
  Timer? _tick;

  DateTime _start(int page) =>
      DateTime(widget.anchor.year, widget.anchor.month, widget.anchor.day + (page - _home) * widget.count);

  /// The names row follows the hours as they are swiped.
  void _follow() {
    if (_body.hasClients && _head.hasClients) _head.jumpTo(_body.position.pixels);
  }

  /// Moves the arrows' way by one page.
  Future<void> pageBy(int dir) => _body.animateToPage(_page + dir, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    // The red "now" line moves on its own.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _body.dispose();
    _head.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final count = widget.count;
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.labelSmall;
    final start = _start(_page);
    final headIndex = CalIndex.build(s.list('items'), start, DateTime(start.year, start.month, start.day + count - 1));
    final headCountdowns = CalIndex.countdowns(s);
    var rows = 0;
    for (var i = 0; i < count; i++) {
      final key = dayKey(DateTime(start.year, start.month, start.day + i));
      final n = (headIndex[key] ?? const <CalEntry>[]).where((e) => e.item['allDay'] == true).length + (headCountdowns[key]?.length ?? 0);
      rows = max(rows, n);
    }
    final headH = 54.0 + min(rows, 3) * 22.0;

    return Column(
        children: [
          SizedBox(
            height: headH,
            child: Row(children: [
              const SizedBox(width: _gutter),
              Expanded(
                child: PageView.builder(
                  controller: _head,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (context, p) => _Head(
                    store: s,
                    start: _start(p),
                    count: count,
                    onDayTap: widget.onDayTap,
                  ),
                ),
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 80),
              child: SizedBox(
                height: _hourH * 24,
                child: Row(children: [
                  SizedBox(
                    width: _gutter,
                    child: Stack(children: [
                      for (var h = 1; h < 24; h++)
                        Positioned(top: h * _hourH - 7, right: 6, child: Text(_hourLabel(h), style: small)),
                    ]),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _body,
                      onPageChanged: (p) {
                        setState(() => _page = p);
                        widget.onVisible(_start(p));
                      },
                      itemBuilder: (context, p) => _BodyPage(
                        store: s,
                        start: _start(p),
                        count: count,
                        scheme: scheme,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ],
      );
  }
}

/// Day names and dates, with the all-day items and countdowns under them.
class _Head extends StatelessWidget {
  const _Head({required this.store, required this.start, required this.count, required this.onDayTap});
  final Store store;
  final DateTime start;
  final int count;
  final void Function(DateTime day) onDayTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = [for (var i = 0; i < count; i++) DateTime(start.year, start.month, start.day + i)];
    final index = CalIndex.build(store.list('items'), days.first, days.last);
    final cds = CalIndex.countdowns(store);
    final today = dayKey(DateTime.now());
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final d in days)
          Expanded(
            child: Column(
              children: [
                InkWell(
                  onTap: () => onDayTap(d),
                  borderRadius: BorderRadius.circular(24),
                  child: Column(children: [
                    Text(_weekdays[d.weekday - 1], style: TextStyle(fontSize: 12, color: dayKey(d) == today ? scheme.primary : null)),
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: dayKey(d) == today ? scheme.primary : Colors.transparent,
                      child: Text('${d.day}',
                          style: TextStyle(fontSize: 16, color: dayKey(d) == today ? scheme.onPrimary : scheme.onSurface)),
                    ),
                  ]),
                ),
                const SizedBox(height: 4),
                for (final e in (index[dayKey(d)] ?? const <CalEntry>[]).where((e) => e.item['allDay'] == true))
                  _chip(
                    context,
                    e.item['title'] as String,
                    eventColor(e.item, scheme).withValues(alpha: e.item['status'] == 'done' ? 0.35 : 1),
                    onEventColor(eventColor(e.item, scheme)),
                    () => showEventView(context, store, e),
                  ),
                for (final c in cds[dayKey(d)] ?? const <Rec>[])
                  _chip(context, c['title'] as String, scheme.secondaryContainer, scheme.onSecondaryContainer, null),
              ],
            ),
          ),
      ],
    );
  }

  Widget _chip(BuildContext context, String text, Color bg, Color fg, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.fromLTRB(1, 0, 1, 2),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          height: 20,
          width: double.infinity,
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: fg)),
        ),
      );
}

class _Drag {
  _Drag(this.entry, {required this.resize});
  final CalEntry entry;
  final bool resize;
  double dx = 0;
  double dy = 0;
}

/// One page of the grid: the hour lines, the blocks, the "now" line and a block being dragged.
class _BodyPage extends StatefulWidget {
  const _BodyPage({required this.store, required this.start, required this.count, required this.scheme});
  final Store store;
  final DateTime start;
  final int count;
  final ColorScheme scheme;

  @override
  State<_BodyPage> createState() => _BodyPageState();
}

class _BodyPageState extends State<_BodyPage> {
  static const _hourH = GridMath.hourH;
  _Drag? _drag;
  ({int col, int minute, int dur})? _ghost;

  int _minuteOf(DateTime d) => d.hour * 60 + d.minute;

  /// Entries are rebuilt on every change, so the same block is found by item and time, not by identity.
  bool _same(CalEntry a, CalEntry b) => a.item['id'] == b.item['id'] && a.start == b.start;

  Future<void> _commit() async {
    final d = _drag;
    setState(() => _drag = null);
    if (d == null) return;
    Haptics.dragEnd();
    final s = widget.store;
    final e = d.entry;
    final dur = CalEdit.minutes(e.item);
    final startMin = _minuteOf(e.start);
    int log;
    if (d.resize) {
      final mins = GridMath.resized(dur, d.dy, startMin);
      if (mins == dur) return;
      log = await CalEdit.resize(s, e, mins);
    } else {
      final colW = _colW;
      final shift = (d.dx / colW).round();
      final minute = GridMath.movedStart(startMin, d.dy, dur);
      if (shift == 0 && minute == startMin) return;
      final day = DateTime(e.start.year, e.start.month, e.start.day + shift);
      log = await CalEdit.move(s, e, DateTime(day.year, day.month, day.day, minute ~/ 60, minute % 60).millisecondsSinceEpoch);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(d.resize ? 'Length changed' : 'Moved'),
        action: SnackBarAction(label: 'Undo', onPressed: () => s.undo(log)),
      ));
  }

  double _colW = 100;

  Future<void> _tapEmpty(TapUpDetails t) async {
    final col = GridMath.columnAt(t.localPosition.dx, _colW, widget.count);
    final minute = GridMath.minuteAt(t.localPosition.dy);
    setState(() => _ghost = (col: col, minute: minute, dur: 60));
    final day = DateTime(widget.start.year, widget.start.month, widget.start.day + col);
    await showQuickAdd(context, widget.store, day: day, at: TimeOfDay(hour: minute ~/ 60, minute: minute % 60), minutes: 60);
    if (mounted) setState(() => _ghost = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final scheme = widget.scheme;
    final count = widget.count;
    final days = [for (var i = 0; i < count; i++) DateTime(widget.start.year, widget.start.month, widget.start.day + i)];
    final index = CalIndex.build(s.list('items'), days.first, days.last);
    final now = DateTime.now();
    final todayCol = days.indexWhere((d) => dayKey(d) == dayKey(now));

    return LayoutBuilder(builder: (context, box) {
      final colW = box.maxWidth / count;
      _colW = colW;
      final blocks = <Widget>[];
      for (var k = 0; k < count; k++) {
        final timed = [for (final e in index[dayKey(days[k])] ?? const <CalEntry>[]) if (e.item['allDay'] != true) e];
        final lanes = GridMath.lanes([
          for (final e in timed) (_minuteOf(e.start), min(_minuteOf(e.start) + CalEdit.minutes(e.item), 24 * 60)),
        ]);
        for (var i = 0; i < timed.length; i++) {
          final e = timed[i];
          final (lane, n) = lanes[i];
          blocks.add(_block(context, e, k, lane, n, colW, scheme));
        }
      }
      final drag = _drag;
      final ghost = _ghost;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _tapEmpty,
              child: CustomPaint(
                painter: _GridPainter(
                  count: count,
                  line: scheme.outlineVariant.withValues(alpha: 0.4),
                  nowMinute: todayCol < 0 ? null : _minuteOf(now),
                  nowCol: todayCol,
                  nowColor: scheme.error,
                ),
              ),
            ),
          ),
          ...blocks,
          if (ghost != null)
            Positioned(
              top: ghost.minute / 60 * _hourH,
              left: ghost.col * colW + 1,
              width: colW - 2,
              height: ghost.dur / 60 * _hourH - 1,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text('(No title)', style: TextStyle(fontSize: 11, color: scheme.onPrimary)),
                  ),
                ),
              ),
            ),
          if (drag != null && !drag.resize) _dragged(drag, colW, scheme),
        ],
      );
    });
  }

  /// The block while it is being carried: lifted, and snapped to quarter hours and to a day column.
  Widget _dragged(_Drag d, double colW, ColorScheme scheme) {
    final e = d.entry;
    final col = _dayIndex(e) + (d.dx / colW).round();
    final dur = CalEdit.minutes(e.item);
    final minute = GridMath.movedStart(_minuteOf(e.start), d.dy, dur);
    final c = eventColor(e.item, scheme);
    return Positioned(
      top: minute / 60 * _hourH,
      left: col.clamp(0, widget.count - 1).toDouble() * colW + 1,
      width: colW - 2,
      height: max(dur / 60 * _hourH, 20.0) - 1,
      child: IgnorePointer(
        child: Material(
          elevation: 6,
          color: c,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              '${e.item['title']}\n${_range(minute, dur)}',
              overflow: TextOverflow.clip,
              style: TextStyle(fontSize: 11, color: onEventColor(c)),
            ),
          ),
        ),
      ),
    );
  }

  int _dayIndex(CalEntry e) {
    final s = DateTime(widget.start.year, widget.start.month, widget.start.day);
    return DateTime(e.start.year, e.start.month, e.start.day).difference(s).inDays;
  }

  String _range(int minute, int dur) {
    final base = DateTime(2000, 1, 1);
    return '${clock(base.add(Duration(minutes: minute)).millisecondsSinceEpoch)} – '
        '${clock(base.add(Duration(minutes: minute + dur)).millisecondsSinceEpoch)}';
  }

  Widget _block(BuildContext context, CalEntry e, int col, int lane, int lanes, double colW, ColorScheme scheme) {
    final it = e.item;
    final startMin = _minuteOf(e.start);
    final dur = CalEdit.minutes(it);
    final d = _drag;
    final mine = d != null && _same(d.entry, e);
    final liveDur = mine && d.resize ? GridMath.resized(dur, d.dy, startMin) : dur;
    final top = startMin / 60 * _hourH;
    final height = min(max(liveDur / 60 * _hourH, 20.0), _hourH * 24 - top + 20) - 1;
    final w = colW / lanes;
    final c = eventColor(it, scheme);
    final fg = onEventColor(c);
    final done = it['status'] == 'done';
    final resizable = it['kind'] != 'alarm';
    return Positioned(
      key: ValueKey('${it['id']}@${e.start.millisecondsSinceEpoch}'),
      top: top,
      left: col * colW + lane * w + 1,
      width: w - 2,
      height: height,
      child: GestureDetector(
        onTap: () => showEventView(context, widget.store, e),
        onLongPressStart: (_) {
          Haptics.dragStart();
          setState(() => _drag = _Drag(e, resize: false));
        },
        onLongPressMoveUpdate: (m) => setState(() {
          _drag?.dx = m.offsetFromOrigin.dx;
          _drag?.dy = m.offsetFromOrigin.dy;
        }),
        onLongPressEnd: (_) => _commit(),
        onLongPressCancel: () => setState(() => _drag = null),
        child: Opacity(
          opacity: mine && !d.resize ? 0.35 : 1,
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
            decoration: BoxDecoration(
              color: c.withValues(alpha: done ? 0.35 : 1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${it['kind'] == 'alarm' ? '⏰ ' : ''}${it['title']}',
                        maxLines: height < 36 ? 1 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: fg,
                          decoration: done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (height >= 40)
                        Text(
                          mine && d.resize ? _range(startMin, liveDur) : _range(startMin, dur),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.85)),
                        ),
                    ],
                  ),
                ),
                if (resizable && height >= 28)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 16,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragStart: (_) {
                        Haptics.dragStart();
                        setState(() => _drag = _Drag(e, resize: true));
                      },
                      onVerticalDragUpdate: (m) => setState(() => _drag?.dy += m.delta.dy),
                      onVerticalDragEnd: (_) => _commit(),
                      onVerticalDragCancel: () => setState(() => _drag = null),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: 22,
                          height: 3,
                          margin: const EdgeInsets.only(bottom: 3),
                          decoration: BoxDecoration(color: fg.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hour lines, day dividers and the red "now" line, drawn in one pass.
class _GridPainter extends CustomPainter {
  _GridPainter({required this.count, required this.line, required this.nowMinute, required this.nowCol, required this.nowColor});
  final int count;
  final Color line;
  final int? nowMinute;
  final int nowCol;
  final Color nowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var h = 0; h < 24; h++) {
      final y = h * GridMath.hourH;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final colW = size.width / count;
    for (var k = 0; k < count; k++) {
      canvas.drawLine(Offset(k * colW, 0), Offset(k * colW, size.height), p);
    }
    final m = nowMinute;
    if (m != null) {
      final y = m / 60 * GridMath.hourH;
      final paint = Paint()
        ..color = nowColor
        ..strokeWidth = 2;
      canvas.drawLine(Offset(nowCol * colW, y), Offset((nowCol + 1) * colW, y), paint);
      canvas.drawCircle(Offset(nowCol * colW, y), 4.5, paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter o) =>
      o.count != count || o.line != line || o.nowMinute != nowMinute || o.nowCol != nowCol || o.nowColor != nowColor;
}
