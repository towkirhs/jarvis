import 'package:flutter/material.dart';

import 'day_log.dart';
import 'haptics.dart';
import 'record_sheet.dart';
import 'store.dart';

/// Add something you did afterwards ("I forgot to log tuition"): what, from, until.
/// Opened from Your day and by tapping an empty slot in the calendar's Done column.
Future<void> showDoneSheet(BuildContext context, Store s, {required DateTime from, DateTime? to}) {
  final what = TextEditingController();
  int? act;
  var start = from;
  var end = to ?? from.add(const Duration(hours: 1));
  String? note;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final tt = Theme.of(ctx).textTheme;
      final scheme = Theme.of(ctx).colorScheme;
      Future<void> pick(bool isStart) async {
        final cur = isStart ? start : end;
        final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(cur));
        if (t == null) return;
        setS(() {
          final d = DateTime(cur.year, cur.month, cur.day, t.hour, t.minute);
          if (isStart) {
            final len = end.difference(start);
            start = d;
            end = d.add(len);
          } else {
            // Ending before it started means it ran past midnight.
            end = d.isAfter(start) ? d : d.add(const Duration(days: 1));
          }
        });
      }

      void save() {
        final w = what.text.trim();
        if (w.isEmpty) return setS(() => note = 'Say what you did.');
        s.addDone(w, start.millisecondsSinceEpoch, end.millisecondsSinceEpoch, act: act);
        Haptics.success();
        Navigator.pop(ctx);
      }

      Widget time(String label, DateTime d, bool isStart) => Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              color: scheme.surfaceContainerHighest,
              child: ListTile(
                title: Text(label, style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                subtitle: Text(clock(d.millisecondsSinceEpoch), style: tt.titleMedium),
                onTap: () => pick(isStart),
              ),
            ),
          );

      final acts = s.list('acts');
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Add what you did', style: tt.headlineSmall),
            const SizedBox(height: 4),
            Text(niceDay(start.millisecondsSinceEpoch), style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            TextField(
              controller: what,
              autofocus: acts.isEmpty,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'What did you do?'),
              onChanged: (_) => act = null,
            ),
            if (acts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final a in acts)
                  ChoiceChip(
                    label: Text('${a['name']}'),
                    showCheckmark: false,
                    selected: act == a['id'],
                    onSelected: (_) => setS(() {
                      what.text = '${a['name']}';
                      act = a['id'] as int;
                    }),
                  ),
              ]),
            ],
            const SizedBox(height: 12),
            Row(children: [time('From', start, true), const SizedBox(width: 12), time('Until', end, false)]),
            if (note != null) ...[
              const SizedBox(height: 8),
              Text(note!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: save, child: const Text('Add'))),
          ]),
        ),
      );
    }),
  );
}

/// Change or delete something you did: its name, when it started and when it ended.
Future<void> editDone(BuildContext context, Store s, Rec e) => showRecordSheet(context, s, 'log', e,
    title: 'What you did',
    fields: [
      const Field('text', 'What', kind: 'long'),
      Field('at', e['verb'] == 'start' || e['verb'] == 'sleep' || e['verb'] == 'back' ? 'Started' : 'When', kind: 'when'),
      if (e['verb'] == 'start' || e['verb'] == 'sleep' || e['verb'] == 'back') const Field('end', 'Ended', kind: 'when', optional: true),
    ],
    name: (r) => DayLog.title(r));
