import 'dart:math';

import 'package:flutter/material.dart';

/// Today at a glance: a strip from morning to night with each timed item as a block, the hours already gone
/// shaded, and a line at now. The gaps are your free time. One line under it says what now is: free or busy.
class DayRibbon extends StatelessWidget {
  const DayRibbon({super.key, required this.items, required this.now, this.onTap});

  /// Today's timed items (open and done). All-day items are not drawn.
  final List<Map<String, dynamic>> items;
  final DateTime now;
  final VoidCallback? onTap;

  static int minutesOf(Map<String, dynamic> i) =>
      ((i['dur'] ?? i['est'] ?? (i['kind'] == 'event' ? 60 : 30)) as int).clamp(10, 24 * 60);

  static String _clock(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return d.minute == 0 ? '$h ${d.hour < 12 ? 'am' : 'pm'}' : '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'am' : 'pm'}';
  }

  static String _span(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    return h == 0 ? '${m}m' : (m == 0 ? '${h}h' : '${h}h ${m}m');
  }

  /// What right now is: inside something, free until the next thing, or clear for the rest of the day.
  static String caption(List<Map<String, dynamic>> items, DateTime now) {
    final open = items.where((i) => i['status'] == 'open' && i['when'] != null).toList()
      ..sort((a, b) => (a['when'] as int).compareTo(b['when'] as int));
    final nowMs = now.millisecondsSinceEpoch;
    for (final i in open) {
      final start = i['when'] as int;
      final end = start + minutesOf(i) * 60000;
      if (start <= nowMs && nowMs < end) {
        return 'Now: ${i['title']}, until ${_clock(DateTime.fromMillisecondsSinceEpoch(end))}';
      }
    }
    final next = open.where((i) => (i['when'] as int) > nowMs).firstOrNull;
    if (next == null) return 'Clear for the rest of the day';
    final gap = ((next['when'] as int) - nowMs) ~/ 60000;
    return '${_span(gap)} free before ${next['title']} at ${_clock(DateTime.fromMillisecondsSinceEpoch(next['when'] as int))}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final day = DateTime(now.year, now.month, now.day);
    // Morning to night, stretched if something is earlier or later.
    var startH = 7, endH = 23;
    for (final i in items) {
      final d = DateTime.fromMillisecondsSinceEpoch(i['when'] as int);
      final endMin = d.hour * 60 + d.minute + minutesOf(i);
      startH = min(startH, d.hour);
      endH = max(endH, min(24, (endMin / 60).ceil()));
    }
    startH = min(startH, now.hour);
    final span = (endH - startH) * 60.0;
    double frac(int minuteOfDay) => ((minuteOfDay - startH * 60) / span).clamp(0.0, 1.0);
    final nowFrac = frac(now.hour * 60 + now.minute);

    return Semantics(
      label: 'Today. ${caption(items, now)}',
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(builder: (context, box) {
                final w = box.maxWidth;
                return SizedBox(
                  height: 44,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      // The part of the day already gone.
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: w * nowFrac,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.onSurface.withValues(alpha: 0.06),
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                          ),
                        ),
                      ),
                      for (final i in items)
                        Builder(builder: (context) {
                          final d = DateTime.fromMillisecondsSinceEpoch(i['when'] as int);
                          final m = d.difference(day).inMinutes;
                          final left = frac(m) * w;
                          final width = max(frac(m + minutesOf(i)) * w - left, 4.0);
                          final done = i['status'] == 'done';
                          final overdue = !done && d.add(Duration(minutes: minutesOf(i))).isBefore(now);
                          final color = done
                              ? scheme.outline.withValues(alpha: 0.35)
                              : overdue
                                  ? scheme.error
                                  : (i['kind'] == 'task' ? scheme.tertiary : scheme.primary);
                          return Positioned(
                            left: left + 1,
                            width: width - 2,
                            top: 6,
                            bottom: 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                            ),
                          );
                        }),
                      Positioned(
                        left: w * nowFrac - 1,
                        top: -4,
                        bottom: -4,
                        child: Container(
                          width: 2,
                          decoration: BoxDecoration(color: scheme.onSurface, borderRadius: BorderRadius.circular(1)),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 4),
              // Hour marks every three hours, placed where they fall.
              LayoutBuilder(builder: (context, box) {
                final style = tt.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
                return SizedBox(
                  height: 16,
                  child: Stack(children: [
                    for (var h = (startH + 2) ~/ 3 * 3; h < endH; h += 3)
                      if (h > startH)
                        Positioned(
                          left: frac(h * 60) * box.maxWidth - 12,
                          width: 24,
                          child: Text(h % 12 == 0 ? '12' : '${h % 12}', textAlign: TextAlign.center, style: style),
                        ),
                  ]),
                );
              }),
              const SizedBox(height: 4),
              Text(caption(items, now), style: tt.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}
