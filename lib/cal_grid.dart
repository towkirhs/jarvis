import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'cal_edit.dart';
import 'cal_event.dart';
import 'cal_index.dart';
import 'cal_quick.dart';
import 'day_log.dart';
import 'done_sheet.dart';
import 'haptics.dart';
import 'native.dart';
import 'store.dart';
import 'task_sheet.dart';
import 'theme.dart' show accents;

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The colour of an item's block: its own colour, else its priority, else its kind.
Color eventColor(Rec it, ColorScheme scheme) {
  final ext = it['extColor'];
  if (ext is int) return Color(ext);
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

/// Minutes from the start of the grid's day to [d]: from midnight, or from 5 am when the day starts then.
int gridMinute(DateTime d, int shift) => ((d.hour * 60 + d.minute - shift) % 1440 + 1440) % 1440;

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
    this.stack = false,
    this.done = false,
    this.apps = false,
  });
  final Store store;

  /// Each day splits in two: the plan on the left, what you really did on the right.
  final bool done;

  /// With [done]: time in apps shows in the Done half too.
  final bool apps;

  /// Events at the same time lie on top of each other (each a step to the right) instead of side by side.
  final bool stack;

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
      ScrollController(initialScrollOffset: _hourH * ((gridMinute(DateTime.now(), widget.store.dayShift) ~/ 60 - 2).clamp(0, 16)));
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
    final headIndex = CalIndex.build(s.calendarItems, start, DateTime(start.year, start.month, start.day + count - 1), shift: s.dayShift);
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
                        Positioned(top: h * _hourH - 7, right: 6, child: Text(_hourLabel((h + s.dayShift ~/ 60) % 24), style: small)),
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
                        stack: widget.stack,
                        done: widget.done,
                        apps: widget.apps,
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
    final index = CalIndex.build(store.calendarItems, days.first, days.last, shift: store.dayShift);
    final cds = CalIndex.countdowns(store);
    final today = dayKey(CalIndex.dayOf(DateTime.now(), store.dayShift));
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
  const _BodyPage({
    required this.store,
    required this.start,
    required this.count,
    required this.scheme,
    this.stack = false,
    this.done = false,
    this.apps = false,
  });
  final bool stack, done, apps;
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

  /// A Done block being moved or stretched: the block, which way, and how far (pixels).
  ({DoneBlock block, bool resize, double dy})? _doneDrag;
  List<AppSession> _appTime = const [];

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    if (!widget.done || !widget.apps || kIsWeb || !await Native.usageAccess()) return;
    final from = _at(widget.start, 0);
    final raw = await Native.appSessions(from, from.add(Duration(days: widget.count)));
    if (mounted) setState(() => _appTime = raw.map(AppSession.from).whereType<AppSession>().toList());
  }

  static int _snap(double dy) => ((dy / _hourH * 60) / 15).round() * 15;

  /// Puts a moved or stretched Done block in place, with Undo.
  Future<void> _commitDone() async {
    final d = _doneDrag;
    setState(() => _doneDrag = null);
    final rec = d?.block.log;
    if (d == null || rec == null) return;
    final delta = _snap(d.dy) * 60000;
    if (delta == 0) return;
    Haptics.dragEnd();
    final b = d.block;
    if (d.resize && b.end + delta - b.start < 5 * 60000) return;
    await widget.store.updateRec('log', rec, '${d.resize ? 'Changed length' : 'Moved'}: ${b.title}', (x) {
      if (x['kind'] == 'check') {
        if (!d.resize) x['from'] = (x['from'] as int) + delta;
        x['at'] = (x['at'] as int) + delta;
      } else if (d.resize) {
        x['end'] = b.end + delta;
      } else {
        x['at'] = (x['at'] as int) + delta;
        if (!b.running) x['end'] = b.end + delta;
      }
    });
    if (!mounted) return;
    final s = widget.store;
    final log = s.list('actions').last['id'] as int;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(d.resize ? 'Length changed' : 'Moved'),
        persist: false,
        action: SnackBarAction(label: 'Undo', onPressed: () => s.undo(log)),
      ));
  }

  int get _shift => widget.store.dayShift;
  int _minuteOf(DateTime d) => gridMinute(d, _shift);

  /// The real time [minute] grid minutes into [day] (5 am + minute when the day starts at 5 am).
  DateTime _at(DateTime day, int minute) => DateTime(day.year, day.month, day.day, 0, _shift + minute);

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
      final from = CalIndex.dayOf(e.start, _shift);
      final day = DateTime(from.year, from.month, from.day + shift);
      log = await CalEdit.move(s, e, _at(day, minute).millisecondsSinceEpoch);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(d.resize ? 'Length changed' : 'Moved'),
        persist: false,
      action: SnackBarAction(label: 'Undo', onPressed: () => s.undo(log)),
      ));
  }

  double _colW = 100;

  Future<void> _tapEmpty(TapUpDetails t) async {
    final col = GridMath.columnAt(t.localPosition.dx, _colW, widget.count);
    final minute = GridMath.minuteAt(t.localPosition.dy);
    // The Done half: add something you did then.
    if (widget.done && t.localPosition.dx - col * _colW > _colW / 2) {
      final from = _at(DateTime(widget.start.year, widget.start.month, widget.start.day + col), minute);
      await showDoneSheet(context, widget.store, from: from, to: from.add(const Duration(hours: 1)));
      return;
    }
    setState(() => _ghost = (col: col, minute: minute, dur: 60));
    final real = _at(DateTime(widget.start.year, widget.start.month, widget.start.day + col), minute);
    await showQuickAdd(context, widget.store, day: real, at: TimeOfDay.fromDateTime(real), minutes: 60);
    if (mounted) setState(() => _ghost = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final scheme = widget.scheme;
    final count = widget.count;
    final days = [for (var i = 0; i < count; i++) DateTime(widget.start.year, widget.start.month, widget.start.day + i)];
    final index = CalIndex.build(s.calendarItems, days.first, days.last, shift: _shift);
    final now = DateTime.now();
    final todayCol = days.indexWhere((d) => dayKey(d) == dayKey(CalIndex.dayOf(now, _shift)));

    return LayoutBuilder(builder: (context, box) {
      final colW = box.maxWidth / count;
      _colW = colW;
      final blocks = <Widget>[];
      for (var k = 0; k < count; k++) {
        final timed = [for (final e in index[dayKey(days[k])] ?? const <CalEntry>[]) if (e.item['allDay'] != true) e];
        final lanes = GridMath.lanes([
          for (final e in timed) (_minuteOf(e.start), min(_minuteOf(e.start) + CalEdit.minutes(e.item), 24 * 60)),
        ]);
        // Lower lanes first, so a later lane is drawn over them.
        final order = [for (var i = 0; i < timed.length; i++) i]..sort((a, b) => lanes[a].$1.compareTo(lanes[b].$1));
        for (final i in order) {
          final (lane, n) = lanes[i];
          blocks.add(_block(context, timed[i], k, lane, n, colW, scheme));
        }
        if (widget.done) {
          final from = _at(days[k], 0);
          final done = DayLog.blocks(s.list('log'), from, from.add(const Duration(days: 1)), now: now, apps: widget.apps ? _appTime : const []);
          final dayMs = from.millisecondsSinceEpoch;
          int minuteOf(int ms) => ((ms - dayMs) ~/ 60000).clamp(0, 24 * 60);
          final dl = GridMath.lanes([for (final b in done) (minuteOf(b.start), max(minuteOf(b.end), minuteOf(b.start) + 15))]);
          for (var i = 0; i < done.length; i++) {
            blocks.add(_doneBlock(context, done[i], k, dl[i].$1, dl[i].$2, colW, minuteOf(done[i].start), minuteOf(done[i].end), scheme));
          }
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
                  split: widget.done ? scheme.surfaceContainerHighest.withValues(alpha: 0.35) : null,
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
              width: (widget.done ? colW / 2 : colW) - 2,
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
      width: (widget.done ? colW / 2 : colW) - 2,
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
    return CalIndex.dayOf(e.start, _shift).difference(s).inDays;
  }

  String _range(int minute, int dur) {
    final base = DateTime(2000, 1, 1, 0, _shift);
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
    // Side by side: each lane gets an equal share. On top of each other: each lane starts a step to the
    // right and runs to the edge, with a thin outline so the one underneath still shows.
    final over = widget.stack && lanes > 1;
    final pw = widget.done ? colW / 2 : colW;
    final step = over ? min(pw * 0.22, pw / lanes) : pw / lanes;
    final w = over ? pw - lane * step : step;
    final c = eventColor(it, scheme);
    final fg = onEventColor(c);
    final done = it['status'] == 'done';
    final resizable = it['kind'] != 'alarm' && it['ext'] == null;
    return Positioned(
      key: ValueKey('${it['id']}@${e.start.millisecondsSinceEpoch}'),
      top: top,
      left: col * colW + lane * step + 1,
      width: w - 2,
      height: height,
      child: GestureDetector(
        onTap: () => showEventView(context, widget.store, e),
        onLongPressStart: it['ext'] != null
            ? null
            : (_) {
                Haptics.dragStart();
                setState(() => _drag = _Drag(e, resize: false));
              },
        onLongPressMoveUpdate: it['ext'] != null
            ? null
            : (m) => setState(() {
                  _drag?.dx = m.offsetFromOrigin.dx;
                  _drag?.dy = m.offsetFromOrigin.dy;
                }),
        onLongPressEnd: it['ext'] != null ? null : (_) => _commit(),
        onLongPressCancel: it['ext'] != null ? null : () => setState(() => _drag = null),
        child: Opacity(
          opacity: mine && !d.resize ? 0.35 : 1,
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 3, 4, 2),
            decoration: BoxDecoration(
              color: over && done ? Color.alphaBlend(c.withValues(alpha: 0.35), scheme.surface) : c.withValues(alpha: done ? 0.35 : 1),
              borderRadius: BorderRadius.circular(8),
              border: over && lane > 0 ? Border.all(color: scheme.surface, width: 1.5) : null,
            ),
            child: Stack(
              children: [
                // A short, narrow block cuts its text off at the bottom instead of overflowing.
                Positioned.fill(
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      maxHeight: double.infinity,
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
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

  /// What you really did, in the right half of a day: tap to change it, hold to move it, pull the bottom to stretch it.
  Widget _doneBlock(BuildContext context, DoneBlock b, int col, int lane, int lanes, double colW, int startMin, int endMin, ColorScheme scheme) {
    final d = _doneDrag;
    final mine = d != null && d.block.log != null && d.block.log?['id'] == b.log?['id'] && d.block.start == b.start;
    var s0 = startMin, e0 = endMin;
    if (mine) {
      final m = _snap(d.dy);
      if (d.resize) {
        e0 = max(s0 + 5, e0 + m);
      } else {
        s0 += m;
        e0 += m;
      }
    }
    const hourH = GridMath.hourH;
    final half = colW / 2;
    final w = half / lanes;
    final top = s0 / 60 * hourH;
    final height = max((e0 - s0) / 60 * hourH, 18.0) - 1;
    final (bg, fg) = switch (b.kind) {
      'app' => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      'sleep' => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _ => (scheme.primaryContainer, scheme.onSurface),
    };
    final rec = b.log;
    final range = b.running ? '${clock(b.start)} – now' : '${clock(b.start)} – ${clock(b.end)}';
    return Positioned(
      key: ValueKey('done${rec?['id'] ?? b.title}@${b.start}'),
      top: top,
      left: col * colW + half + lane * w + 1,
      width: w - 2,
      height: height,
      child: GestureDetector(
        onTap: rec == null ? null : () => editDone(context, widget.store, rec),
        onLongPressStart: rec == null
            ? null
            : (_) {
                Haptics.dragStart();
                setState(() => _doneDrag = (block: b, resize: false, dy: 0));
              },
        onLongPressMoveUpdate: rec == null ? null : (m) => setState(() => _doneDrag = (block: b, resize: false, dy: m.offsetFromOrigin.dy)),
        onLongPressEnd: rec == null ? null : (_) => _commitDone(),
        onLongPressCancel: rec == null ? null : () => setState(() => _doneDrag = null),
        child: Container(
          padding: const EdgeInsets.fromLTRB(5, 2, 3, 2),
          decoration: BoxDecoration(
            color: bg.withValues(alpha: mine ? 0.7 : 1),
            borderRadius: BorderRadius.circular(8),
            border: b.running ? Border.all(color: scheme.primary, width: 1.5) : null,
          ),
          child: Stack(children: [
            Positioned.fill(
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  maxHeight: double.infinity,
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      b.title,
                      maxLines: height < 36 ? 1 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, fontWeight: b.kind == 'app' ? FontWeight.w400 : FontWeight.w600, color: fg),
                    ),
                    if (height >= 40)
                      Text(range, maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.8))),
                  ]),
                ),
              ),
            ),
            if (rec != null && height >= 28)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 14,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragStart: (_) {
                    Haptics.dragStart();
                    setState(() => _doneDrag = (block: b, resize: true, dy: 0));
                  },
                  onVerticalDragUpdate: (m) => setState(() => _doneDrag = (block: b, resize: true, dy: (_doneDrag?.dy ?? 0) + m.delta.dy)),
                  onVerticalDragEnd: (_) => _commitDone(),
                  onVerticalDragCancel: () => setState(() => _doneDrag = null),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 18,
                      height: 3,
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(color: fg.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Hour lines, day dividers and the red "now" line, drawn in one pass.
class _GridPainter extends CustomPainter {
  _GridPainter({required this.count, required this.line, required this.nowMinute, required this.nowCol, required this.nowColor, this.split});
  final int count;

  /// The Done half's shade, when each day is split into plan and done.
  final Color? split;
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
    final tint = split;
    if (tint != null) {
      for (var k = 0; k < count; k++) {
        canvas.drawRect(Rect.fromLTWH(k * colW + colW / 2, 0, colW / 2, size.height), Paint()..color = tint);
      }
    }
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
      o.count != count || o.split != split || o.line != line || o.nowMinute != nowMinute || o.nowCol != nowCol || o.nowColor != nowColor;
}
