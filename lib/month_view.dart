import 'package:flutter/material.dart';

import 'store.dart';

/// The whole month at a glance: a grid of days, Monday first, with a dot for each thing planned.
/// Tap a day to open it.
class MonthView extends StatelessWidget {
  const MonthView({super.key, required this.store, required this.month, required this.onDayTap});
  final Store store;

  /// Any day in the month to show.
  final DateTime month;
  final void Function(DateTime day) onDayTap;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// The weeks to draw: whole weeks, Monday first, that cover [month].
  static List<List<DateTime>> weeks(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final start = DateTime(first.year, first.month, first.day - (first.weekday - 1));
    final end = DateTime(last.year, last.month, last.day + (7 - last.weekday));
    final days = end.difference(start).inDays + 1;
    // Counted in calendar days (not 24-hour steps) so a clock change never skips or repeats a day.
    final all = [for (var i = 0; i < days; i++) DateTime(start.year, start.month, start.day + i)];
    return [for (var i = 0; i < all.length; i += 7) all.sublist(i, i + 7)];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final today = dayKey(DateTime.now());
    final byDay = <String, List<Rec>>{};
    for (final i in store.list('items')) {
      final w = i['when'] as int?;
      if (w == null || i['status'] == 'cancelled') continue;
      (byDay[dayKey(fromMs(w))] ??= []).add(i);
    }
    final marked = <String>{for (final c in store.list('countdowns')) dayKey(store.countdownNext(c))};

    Color colorOf(Rec i) => switch (i['kind']) {
          'event' => scheme.primary,
          'alarm' => Colors.orange,
          _ => scheme.tertiary,
        };

    Widget cell(DateTime d) {
      final key = dayKey(d);
      final items = byDay[key] ?? const <Rec>[];
      final inMonth = d.month == month.month;
      final isToday = key == today;
      final shown = items.take(4).toList();
      return Expanded(
        child: InkWell(
          onTap: () => onDayTap(d),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5), width: 0.5),
                left: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5), width: 0.5),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 2),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: isToday ? scheme.primary : Colors.transparent,
                  child: Text(
                    '${d.day}',
                    style: text.labelMedium?.copyWith(
                      color: isToday ? scheme.onPrimary : (inMonth ? null : scheme.onSurface.withValues(alpha: 0.35)),
                      fontWeight: isToday ? FontWeight.bold : null,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    for (final i in shown)
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorOf(i).withValues(alpha: i['status'] == 'done' ? 0.3 : (inMonth ? 1 : 0.5)),
                        ),
                      ),
                    if (marked.contains(key)) Icon(Icons.cake_outlined, size: 8, color: scheme.secondary),
                  ],
                ),
                if (items.length > shown.length)
                  Text('+${items.length - shown.length}', style: text.labelSmall?.copyWith(fontSize: 9)),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              for (final w in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(w, style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Column(
              children: [
                for (final week in weeks(month)) Expanded(child: Row(children: [for (final d in week) cell(d)])),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Wrap(
            spacing: 14,
            children: [
              for (final (name, color) in [('Event', scheme.primary), ('Task', scheme.tertiary), ('Alarm', Colors.orange)])
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                  const SizedBox(width: 4),
                  Text(name, style: text.labelSmall),
                ]),
            ],
          ),
        ),
      ],
    );
  }
}
