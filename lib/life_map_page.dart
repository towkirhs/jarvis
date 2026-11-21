import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'areas.dart';
import 'day_log.dart';
import 'haptics.dart';
import 'native.dart';
import 'store.dart';

/// The Life map: the areas of your life on a target. Drag an area towards the middle when it matters most
/// this season, to the edge when it only needs keeping up. Its ring is how it is going; its size is the
/// time Your day shows you gave it. Below: today or this week by area, and what does not line up.
class LifeMapPage extends StatefulWidget {
  const LifeMapPage({super.key, required this.store});
  final Store store;

  @override
  State<LifeMapPage> createState() => _LifeMapPageState();
}

class _LifeMapPageState extends State<LifeMapPage> {
  Store get s => widget.store;
  bool _week = true;
  List<AppSession> _apps = const [];
  final _drag = <int, Offset>{}; // area id -> where it is while being dragged (0..1)
  String? _said;

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    if (kIsWeb) return;
    try {
      if (!await Native.usageAccess()) return;
      final now = DateTime.now();
      final raw = await Native.appSessions(now.subtract(const Duration(days: 7)), now);
      if (mounted) setState(() => _apps = raw.map(AppSession.from).whereType<AppSession>().toList());
    } catch (_) {}
  }

  Color _ring(ColorScheme c, Rec a) => switch (a['status']) {
        'good' => c.primary,
        'ok' => c.tertiary,
        'bad' => c.error,
        _ => c.outline,
      };

  Map<int, int> _minutes(DateTime from, DateTime to, {bool apps = true}) => Areas.minutes(s.list('areas'),
      log: s.list('log'), items: s.list('items'), from: from, to: to, now: DateTime.now(), apps: apps ? _apps : const []);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final areas = s.list('areas');
          final now = DateTime.now();
          final week = _minutes(now.subtract(const Duration(days: 7)), now);
          return Scaffold(
            appBar: AppBar(title: const Text('Life map')),
            floatingActionButton: areas.isEmpty
                ? null
                : FloatingActionButton.extended(onPressed: () => _edit(null), icon: const Icon(Icons.add), label: const Text('Area')),
            body: areas.isEmpty
                ? _empty(context)
                : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
                    _board(context, areas, week),
                    if (_said != null)
                      Padding(padding: const EdgeInsets.fromLTRB(4, 10, 4, 0), child: Text(_said!, style: Theme.of(context).textTheme.bodyMedium)),
                    const SizedBox(height: 16),
                    _summary(context, areas, week),
                  ]),
          );
        },
      );

  Widget _empty(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.track_changes, size: 56, color: scheme.primary),
          const SizedBox(height: 16),
          Text('Map the areas of your life', style: tt.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Put what matters this season in the middle and the rest at the edge. Plan my day, Your day and the chat all use it.',
            style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              final undo = <Rec>[];
              for (final a in Areas.starters()) {
                final r = {'id': s.nextId(), ...a};
                s.list('areas').add(r);
                undo.add({'op': 'rm', 'col': 'areas', 'id': r['id']});
              }
              s.logAction('Added the usual areas', undo);
              s.save();
              Haptics.success();
              setState(() => _said = 'Drag each area: the middle is this season\'s focus, the edge is maintenance. Tap one to rename it or change its words.');
            },
            child: const Text('Start with the usual ones'),
          ),
          TextButton(onPressed: () => _edit(null), child: const Text('Add one myself')),
        ]),
      ),
    );
  }

  Widget _board(BuildContext context, List<Rec> areas, Map<int, int> week) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, box) {
      final size = min(box.maxWidth, 440.0);
      return Center(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: CustomPaint(painter: _Target(scheme))),
            Positioned(left: 14, top: 10, child: Text('Life', style: tt.labelLarge?.copyWith(color: scheme.onSurfaceVariant))),
            Positioned(right: 14, top: 10, child: Text('Work', style: tt.labelLarge?.copyWith(color: scheme.onSurfaceVariant))),
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Text('Maintenance', textAlign: TextAlign.center, style: tt.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            ),
            for (final a in areas) _bubble(context, a, size, week[a['id']] ?? 0),
          ]),
        ),
      );
    });
  }

  Widget _bubble(BuildContext context, Rec a, double size, int minutes) {
    final scheme = Theme.of(context).colorScheme;
    final id = a['id'] as int;
    final at = _drag[id] ?? Offset(((a['x'] as num?) ?? 0.5).toDouble(), ((a['y'] as num?) ?? 0.5).toDouble());
    // Bigger with more time this week, so a big bubble at the edge or a small one in the middle stands out.
    final r = 24 + min(22.0, sqrt(minutes / 60) * 7);
    return Positioned(
      left: at.dx * size - r,
      top: at.dy * size - r,
      child: Semantics(
        button: true,
        onTap: () => _edit(a),
        label: '${a['name']}, ${Areas.zones[Areas.zone(a)]}, ${Areas.hm(minutes)} this week',
        // Claims the touch at once, so dragging a bubble never scrolls the page; a touch that barely moves is a tap.
        child: RawGestureDetector(
          gestures: {
            TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              TapGestureRecognizer.new,
              (g) => g.onTap = () => _edit(a),
            ),
            ImmediateMultiDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<ImmediateMultiDragGestureRecognizer>(
              ImmediateMultiDragGestureRecognizer.new,
              (g) => g.onStart = (_) {
                var moved = 0.0;
                return _BubbleDrag(
                  (d) => setState(() {
                    moved += d.delta.distance;
                    final p = (_drag[id] ?? at) + Offset(d.delta.dx / size, d.delta.dy / size);
                    _drag[id] = Offset(p.dx.clamp(0.04, 0.96), p.dy.clamp(0.04, 0.96));
                  }),
                  () async {
                    final p = _drag.remove(id);
                    if (moved < 8 || p == null) {
                      if (mounted) setState(() {});
                      return _edit(a);
                    }
                    Haptics.tap();
                    await s.updateRec('areas', a, 'Moved ${a['name']}', (x) {
                      x['x'] = (p.dx * 1000).round() / 1000;
                      x['y'] = (p.dy * 1000).round() / 1000;
                    });
                    if (mounted) setState(() => _said = _whatItDoes(a, minutes));
                  },
                );
              },
            ),
          },
          child: Container(
            width: r * 2,
            height: r * 2,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.surfaceContainerLow,
              border: Border.all(color: _ring(scheme, a), width: 3),
            ),
            child: FittedBox(
              child: Text('${a['name']}', maxLines: 1, style: Theme.of(context).textTheme.labelMedium),
            ),
          ),
        ),
      ),
    );
  }

  String _whatItDoes(Rec a, int minutes) {
    final z = Areas.zone(a);
    final name = a['name'];
    final base = '$name: ${Areas.zones[z]!.toLowerCase()} (focus ${Areas.focus(a)}).';
    if (z == 'focus') {
      return '$base Plan my day places its tasks first${minutes < 120 ? ', and it only got ${Areas.hm(minutes)} this week' : ''}.';
    }
    if (z == 'maintenance') return '$base Its habits keep going; Plan my day gives its other tasks the time left over.';
    return '$base Its tasks come after your main focus.';
  }

  Widget _summary(BuildContext context, List<Rec> areas, Map<int, int> week) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final shown = _week ? week : _minutes(_dayStart(now), now);
    final total = shown.values.fold<int>(0, (a, b) => a + b);
    final sorted = [...areas]..sort((a, b) => Areas.focus(b).compareTo(Areas.focus(a)));
    final notes = _week ? Areas.notes(areas, week, _minutes(now.subtract(const Duration(days: 21)), now, apps: false)) : const <String>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<bool>(
        segments: const [ButtonSegment(value: false, label: Text('Today')), ButtonSegment(value: true, label: Text('This week'))],
        selected: {_week},
        onSelectionChanged: (v) => setState(() => _week = v.first),
      ),
      const SizedBox(height: 12),
      for (final n in notes)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: scheme.primaryContainer,
          child: ListTile(leading: Icon(Icons.compare_arrows, color: scheme.primary), title: Text(n, style: tt.bodyMedium)),
        ),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(total == 0 ? 'Nothing logged ${_week ? 'this week' : 'today'} yet' : '${Areas.hm(total)} logged ${_week ? 'this week' : 'today'}',
                style: tt.titleMedium),
            if (total == 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Your day fills this in: "started gym", your buttons, check-ins and time in apps.',
                    style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            const SizedBox(height: 8),
            for (final a in sorted) _row(context, '${a['name']}', Areas.zones[Areas.zone(a)]!, shown[a['id']] ?? 0, total, _ring(scheme, a)),
            if ((shown[0] ?? 0) > 0) _row(context, 'No area', 'words match no area', shown[0]!, total, scheme.outlineVariant),
          ]),
        ),
      ),
    ]);
  }

  static DateTime _dayStart(DateTime now) {
    final d = DayStart.of(now);
    return DateTime(d.year, d.month, d.day).add(Duration(minutes: DayStart.minutes));
  }

  Widget _row(BuildContext context, String name, String note, int m, int total, Color color) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(name, style: tt.bodyLarge)),
          Text(note, style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(width: 10),
          SizedBox(width: 56, child: Text(Areas.hm(m), textAlign: TextAlign.end, style: tt.labelLarge)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: total == 0 ? 0 : m / total, minHeight: 6, color: color, backgroundColor: scheme.surfaceContainerHighest),
        ),
      ]),
    );
  }

  Future<void> _edit(Rec? a) async {
    final name = TextEditingController(text: a?['name'] as String? ?? '');
    final words = TextEditingController(text: ((a?['words'] as List?) ?? const []).join(', '));
    final note = TextEditingController(text: a?['note'] as String? ?? '');
    var work = a == null ? false : Areas.isWork(a);
    var zone = a == null ? 'side' : Areas.zone(a);
    var status = a?['status'] as String?;
    final areas = s.list('areas');
    final inIt = a == null
        ? const <String>[]
        : [
            for (final i in s.list('items'))
              if (i['status'] == 'open' && Areas.of(areas, i)?['id'] == a['id']) '${i['title']}',
            for (final h in s.list('habits'))
              if (h['archived'] != true && Areas.of(areas, h)?['id'] == a['id']) 'Habit: ${h['name']}',
          ];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final tt = Theme.of(ctx).textTheme;
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(a == null ? 'New area' : '${a['name']}', style: tt.headlineSmall),
                const SizedBox(height: 12),
                TextField(
                  controller: name,
                  autofocus: a == null,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: words,
                  decoration: const InputDecoration(
                    labelText: 'Words that mean this area',
                    hintText: 'gym, walk, doctor',
                    helperText: 'Tasks, habits, Your day and apps with these words count here',
                  ),
                ),
                const SizedBox(height: 14),
                SegmentedButton<bool>(
                  segments: const [ButtonSegment(value: false, label: Text('Life')), ButtonSegment(value: true, label: Text('Work'))],
                  selected: {work},
                  onSelectionChanged: (v) => setS(() => work = v.first),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final z in Areas.zones.entries)
                    ChoiceChip(label: Text(z.value), selected: zone == z.key, onSelected: (_) => setS(() => zone = z.key)),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final st in Areas.statuses.entries)
                    ChoiceChip(label: Text(st.value), selected: status == st.key, onSelected: (_) => setS(() => status = status == st.key ? null : st.key)),
                ]),
                const SizedBox(height: 10),
                TextField(controller: note, maxLines: 3, minLines: 1, decoration: const InputDecoration(labelText: 'Note')),
                if (inIt.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('In this area (${inIt.length})', style: tt.titleSmall),
                  const SizedBox(height: 4),
                  for (final t in inIt.take(6)) Text('• $t', style: tt.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (inIt.length > 6) Text('and ${inIt.length - 6} more', style: tt.bodySmall),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  if (a != null)
                    TextButton(
                      onPressed: () {
                        s.removeRec('areas', a, 'Deleted area ${a['name']}');
                        Navigator.pop(ctx);
                      },
                      child: const Text('Delete'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () async {
                      final n = name.text.trim();
                      if (n.isEmpty) return Haptics.reject();
                      void fill(Rec r) {
                        r['name'] = n;
                        r['words'] = words.text.split(',').map((w) => w.trim().toLowerCase()).where((w) => w.isNotEmpty).toList();
                        // Keep where you dragged it unless the zone or side changed.
                        if (r['x'] == null || Areas.zone(r) != zone || Areas.isWork(r) != work) {
                          final p = Areas.place(r, zone, work: work);
                          r['x'] = (p.x * 1000).round() / 1000;
                          r['y'] = (p.y * 1000).round() / 1000;
                        }
                        r['status'] = status;
                        r['note'] = note.text.trim().isEmpty ? null : note.text.trim();
                      }

                      if (a == null) {
                        final r = <String, dynamic>{'id': s.nextId(), 'y': 0.3 + Random().nextDouble() * 0.4};
                        r['x'] = work ? 0.7 : 0.3;
                        fill(r);
                        s.list('areas').add(r);
                        s.logAction('Added area $n', [{'op': 'rm', 'col': 'areas', 'id': r['id']}]);
                        s.save();
                      } else {
                        await s.updateRec('areas', a, 'Changed area $n', fill);
                      }
                      Haptics.success();
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Save'),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _BubbleDrag extends Drag {
  _BubbleDrag(this.onUpdate, this.onEnd);
  final void Function(DragUpdateDetails) onUpdate;
  final Future<void> Function() onEnd;

  @override
  void update(DragUpdateDetails details) => onUpdate(details);

  @override
  void end(DragEndDetails details) => onEnd();

  @override
  void cancel() {}
}

/// The target: three rings, the middle washed with the accent, and a line between life and work.
class _Target extends CustomPainter {
  _Target(this.c);
  final ColorScheme c;

  @override
  void paint(Canvas canvas, Size size) {
    final o = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(o, r, Paint()..color = c.surfaceContainerLow);
    canvas.drawCircle(o, r * 0.67, Paint()..color = c.surfaceContainerHighest.withValues(alpha: 0.5));
    canvas.drawCircle(o, r * 0.34, Paint()..color = c.primaryContainer);
    final line = Paint()
      ..color = c.outlineVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final f in [1.0, 0.67, 0.34]) {
      canvas.drawCircle(o, r * f - 0.5, line);
    }
    for (var y = 6.0; y < size.height - 6; y += 10) {
      canvas.drawLine(Offset(o.dx, y), Offset(o.dx, y + 5), line);
    }
  }

  @override
  bool shouldRepaint(_Target old) => old.c != c;
}
