import 'package:flutter/material.dart';

import 'clash.dart';
import 'clock.dart';
import 'haptics.dart';
import 'store.dart';
import 'task_sheet.dart';

/// A small sheet to add something in two taps: a title, and when. "More options" opens the full form with what
/// is already filled in, so nothing typed is lost.
Future<void> showQuickAdd(
  BuildContext context,
  Store s, {
  required DateTime day,
  TimeOfDay? at,
  int minutes = 60,
  String kind = 'event',
}) {
  final title = TextEditingController();
  var date = DateTime(day.year, day.month, day.day);
  TimeOfDay? start = at;
  var mins = minutes;
  var what = kind;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        TimeOfDay? end() {
          if (start == null) return null;
          final total = start!.hour * 60 + start!.minute + mins;
          return TimeOfDay(hour: (total ~/ 60) % 24, minute: total % 60);
        }

        int? startMs() => start == null ? null : DateTime(date.year, date.month, date.day, start!.hour, start!.minute).millisecondsSinceEpoch;

        Future<void> pickDate() async {
          final now = DateTime.now();
          final d = await showDatePicker(
            context: ctx,
            initialDate: date,
            firstDate: DateTime(now.year - 1),
            lastDate: DateTime(now.year + 5),
          );
          if (d != null) setS(() => date = d);
        }

        Future<void> pickStart() async {
          final t = await showTimePicker(context: ctx, initialTime: start ?? const TimeOfDay(hour: 9, minute: 0));
          if (t != null) setS(() => start = t);
        }

        Future<void> pickEnd() async {
          final s0 = start!;
          final t = await showTimePicker(context: ctx, initialTime: end() ?? s0);
          if (t == null) return;
          var diff = (t.hour * 60 + t.minute) - (s0.hour * 60 + s0.minute);
          if (diff <= 0) diff += 24 * 60;
          setS(() => mins = diff);
        }

        Future<void> save() async {
          final name = title.text.trim();
          if (name.isEmpty) {
            Haptics.reject();
            return;
          }
          final when = startMs() ?? date.millisecondsSinceEpoch + 9 * 3600000;
          final allDay = start == null;
          final undo = <Rec>[];
          await s.addItem(
            kind: what,
            title: name,
            when: when,
            est: what == 'task' ? mins : null,
            undo: undo,
            extra: {
              'dur': what == 'task' || allDay ? null : mins,
              'allDay': allDay,
              'lead': what == 'alarm' || allDay ? 0 : Lead.defaultFor(s.settings),
            },
          );
          s.logAction('Added: $name', undo);
          s.save();
          Haptics.tap();
          if (ctx.mounted) Navigator.pop(ctx);
          await Clock.sync(s);
        }

        void more() {
          final name = title.text.trim();
          Navigator.pop(ctx);
          showTaskSheet(context, s, presetTitle: name, day: date, at: start, newKind: what, presetMinutes: mins);
        }

        final clash = what == 'event' && start != null
            ? Clash.sentence(Clash.find(s.list('items'), startMs()!, mins), clock)
            : '';
        final scheme = Theme.of(ctx).colorScheme;
        final tt = Theme.of(ctx).textTheme;
        // One row of the "when" card: an icon, what it is, and its value on the right.
        Widget row(IconData icon, String name, Widget trailing, {VoidCallback? onTap}) => InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  height: 52,
                  child: Row(children: [
                    Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(child: Text(name, style: tt.bodyLarge)),
                    trailing,
                  ]),
                ),
              ),
            );
        Widget value(String text) => Text(text, style: tt.bodyLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600));
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => save(),
                style: tt.titleMedium,
                decoration: const InputDecoration(hintText: 'Add title'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'event', label: Text('Event')),
                  ButtonSegment(value: 'task', label: Text('Task')),
                  ButtonSegment(value: 'alarm', label: Text('Alarm')),
                ],
                selected: {what},
                onSelectionChanged: (v) => setS(() => what = v.first),
              ),
              const SizedBox(height: 12),
              Material(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  row(Icons.calendar_today, 'Date', value(niceDay(date.millisecondsSinceEpoch)), onTap: pickDate),
                  const Divider(indent: 48),
                  row(
                    Icons.wb_sunny_outlined,
                    'All day',
                    Switch(
                      value: start == null,
                      onChanged: (v) => setS(() => start = v ? null : (at ?? TimeOfDay(hour: (TimeOfDay.now().hour + 1) % 24, minute: 0))),
                    ),
                  ),
                  if (start != null) ...[
                    const Divider(indent: 48),
                    row(Icons.schedule, 'Starts', value(start!.format(ctx)), onTap: pickStart),
                    if (what != 'alarm') ...[
                      const Divider(indent: 48),
                      row(Icons.schedule_outlined, 'Ends', value(end()!.format(ctx)), onTap: pickEnd),
                    ],
                  ],
                ]),
              ),
              if (clash.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: scheme.tertiary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(clash, style: tt.bodySmall?.copyWith(color: scheme.tertiary))),
                  ]),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: more,
                      child: const Text('More options'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: save,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}
