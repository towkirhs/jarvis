import 'package:flutter/material.dart';

import 'cal_edit.dart';
import 'cal_grid.dart' show eventColor;
import 'cal_index.dart';
import 'clash.dart';
import 'haptics.dart';
import 'phone_calendar.dart';
import 'store.dart';
import 'task_sheet.dart';

/// "9:00 am – 10:30 am" for a timed item, the date for an all-day one (with its last day if it spans several).
String eventWhen(CalEntry e) {
  final it = e.item;
  if (it['allDay'] == true) {
    final span = (it['span'] as num?)?.toInt() ?? 1;
    final from = DateTime(e.start.year, e.start.month, e.start.day);
    if (span <= 1) return '${niceDay(from.millisecondsSinceEpoch)}, all day';
    final to = DateTime(from.year, from.month, from.day + span - 1);
    return '${niceDay(from.millisecondsSinceEpoch)} – ${niceDay(to.millisecondsSinceEpoch)}';
  }
  final start = e.start.millisecondsSinceEpoch;
  if (it['kind'] == 'alarm' || (it['dur'] == null && it['kind'] != 'task')) return niceWhen(start);
  final mins = CalEdit.minutes(it);
  return '${niceDay(start)}, ${clock(start)} – ${clock(start + mins * 60000)}';
}

/// What an item is, read-only, with the things you do to it. Opened by a tap on its block.
Future<void> showEventView(BuildContext context, Store s, CalEntry e) {
  final it = e.item;
  final repeating = it['repeat'] != null;
  final ext = it['ext'] as Map?;
  final scheme = Theme.of(context).colorScheme;
  final text = Theme.of(context).textTheme;
  final colour = eventColor(it, scheme);
  final open = it['status'] == 'open';
  final lead = (it['lead'] as num?)?.toInt() ?? 0;
  final desc = it['desc'] as String?;
  final location = it['location'] as String?;
  final tags = ((it['tags'] as List?) ?? []).cast<String>();
  final place = it['place'] == null ? null : s.list('places').where((p) => p['id'] == it['place']).firstOrNull;

  Widget row(IconData icon, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(child: Text(label, style: text.bodyLarge)),
        ]),
      );

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                it['title'] as String,
                style: text.titleLarge?.copyWith(decoration: open ? null : TextDecoration.lineThrough),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          row(Icons.schedule, eventWhen(e)),
          if (repeating) row(Icons.repeat, repeatNames[it['repeat']] ?? '${it['repeat']}'),
          if (location != null && location.isNotEmpty) row(Icons.place_outlined, location),
          if (place != null) row(Icons.my_location, '${it['placeWhen'] == 'leave' ? 'Leaving' : 'At'} ${place['name']}'),
          if (lead > 0 && it['kind'] != 'alarm') row(Icons.notifications_none, Lead.name(lead)),
          if (desc != null && desc.isNotEmpty) row(Icons.notes, desc),
          if (tags.isNotEmpty) row(Icons.sell_outlined, tags.map((t) => '#$t').join(' ')),
          if ((it['list'] ?? 'Inbox') != 'Inbox') row(Icons.list_alt, '${it['list']}'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: ext != null
                ? [
                    // An event from the phone's calendar is changed in the Calendar app.
                    FilledButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open in Calendar'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        PhoneCalendarApi.open(ext['ev'] as int);
                      },
                    ),
                  ]
                : [
              FilledButton.icon(
                icon: const Icon(Icons.edit_outlined),
                label: Text(repeating ? 'Edit all' : 'Edit'),
                onPressed: () {
                  Navigator.pop(ctx);
                  showTaskSheet(context, s, item: it);
                },
              ),
              if (repeating)
                OutlinedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final r = await CalEdit.detach(s, e);
                    if (context.mounted) showTaskSheet(context, s, item: r.copy);
                  },
                  child: const Text('Edit this date'),
                ),
              if (open && it['kind'] == 'task')
                OutlinedButton(
                  onPressed: () {
                    Haptics.success();
                    Navigator.pop(ctx);
                    s.markDone(it);
                  },
                  child: const Text('Done'),
                ),
              if (repeating)
                TextButton(
                  onPressed: () async {
                    Haptics.warn();
                    Navigator.pop(ctx);
                    final log = await CalEdit.skipDate(s, e);
                    if (context.mounted) _undo(context, s, 'Skipped ${niceDay(e.start.millisecondsSinceEpoch)}', log);
                  },
                  child: const Text('Skip this date'),
                ),
              TextButton(
                onPressed: () {
                  Haptics.warn();
                  Navigator.pop(ctx);
                  s.removeRec('items', it, 'Deleted: ${it['title']}');
                  if (context.mounted) _undo(context, s, repeating ? 'Deleted all dates' : 'Deleted', s.list('actions').last['id'] as int);
                },
                child: Text(repeating ? 'Delete all' : 'Delete'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

void _undo(BuildContext context, Store s, String message, int log) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: SnackBarAction(label: 'Undo', onPressed: () => s.undo(log)),
    ));
}
