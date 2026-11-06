import 'package:flutter/material.dart';

import 'haptics.dart';
import 'store.dart';

const priorityNames = ['None', 'Low', 'Medium', 'High'];
const priorityColors = [Colors.grey, Colors.blue, Colors.orange, Colors.red];
const repeatNames = {null: 'No repeat', 'daily': 'Daily', 'weekly': 'Weekly', 'monthly': 'Monthly', 'yearly': 'Yearly'};

/// Names of all lists in use, Inbox first.
List<String> allLists(Store s) {
  final names = {'Inbox', for (final i in s.list('items')) (i['list'] as String?) ?? 'Inbox'};
  return names.toList();
}

/// Adds a task (or edits [item]) by hand. [day], [at] and [newKind] preset a new one.
/// Start and end times are optional: a date alone is an all-day item; the end sets the duration.
Future<void> showTaskSheet(BuildContext context, Store s, {Rec? item, DateTime? day, TimeOfDay? at, String? newKind, int? presetMinutes}) {
  final title = TextEditingController(text: item?['title'] as String? ?? '');
  final desc = TextEditingController(text: item?['desc'] as String? ?? '');
  final tags = TextEditingController(text: ((item?['tags'] as List?) ?? []).join(', '));
  final listCtrl = TextEditingController(text: (item?['list'] as String?) ?? 'Inbox');
  var kind = (item?['kind'] as String?) ?? newKind ?? 'task';
  var priority = (item?['priority'] as int?) ?? 0;
  var repeat = item?['repeat'] as String?;
  final w = item?['when'] as int?;
  DateTime? date = w != null ? fromMs(w) : day;
  TimeOfDay? time = w != null ? (item?['allDay'] == true ? null : TimeOfDay.fromDateTime(fromMs(w))) : at;
  final oldMinutes = item == null ? presetMinutes : (kind == 'task' ? item['est'] : item['dur']);
  // Whole and half hours of an hour or more are shown in hours.
  var unit = oldMinutes is int && oldMinutes >= 60 && oldMinutes % 30 == 0 ? 'h' : 'min';
  final minutes = TextEditingController(
    text: oldMinutes == null ? '' : (unit == 'h' ? '${(oldMinutes as int) / 60}'.replaceAll('.0', '') : '$oldMinutes'),
  );

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        Future<void> pickDate() async {
          final now = DateTime.now();
          final d = await showDatePicker(
            context: ctx,
            initialDate: date ?? now,
            firstDate: DateTime(now.year - 1),
            lastDate: DateTime(now.year + 5),
          );
          if (d != null) setS(() => date = d);
        }

        Future<void> pickTime() async {
          final t = await showTimePicker(context: ctx, initialTime: time ?? const TimeOfDay(hour: 9, minute: 0));
          if (t != null) setS(() => time = t);
        }

        int? currentMinutes() {
          final a = double.tryParse(minutes.text.trim());
          return a == null ? null : (unit == 'h' ? a * 60 : a).round();
        }

        TimeOfDay? endTime() {
          final m = currentMinutes();
          if (time == null || m == null) return null;
          final total = time!.hour * 60 + time!.minute + m;
          return TimeOfDay(hour: (total ~/ 60) % 24, minute: total % 60);
        }

        // Picking an end time sets the duration field (shown in hours when it is whole or half hours).
        Future<void> pickEnd() async {
          final start = time!;
          final t = await showTimePicker(
            context: ctx,
            initialTime: endTime() ?? TimeOfDay(hour: (start.hour + 1) % 24, minute: start.minute),
          );
          if (t == null) return;
          var diff = (t.hour * 60 + t.minute) - (start.hour * 60 + start.minute);
          if (diff <= 0) diff += 24 * 60;
          setS(() {
            unit = diff >= 60 && diff % 30 == 0 ? 'h' : 'min';
            minutes.text = unit == 'h' ? '${diff / 60}'.replaceAll('.0', '') : '$diff';
          });
        }

        Future<void> save() async {
          final name = title.text.trim();
          if (name.isEmpty) return;
          int? when;
          if (date != null) {
            when = DateTime(date!.year, date!.month, date!.day, time?.hour ?? 9, time?.minute ?? 0)
                .millisecondsSinceEpoch;
          }
          final amount = double.tryParse(minutes.text.trim());
          final mins = amount == null ? null : (unit == 'h' ? amount * 60 : amount).round();
          final fields = <String, dynamic>{
            'desc': desc.text.trim().isEmpty ? null : desc.text.trim(),
            'priority': priority,
            'tags': tags.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
            'list': listCtrl.text.trim().isEmpty ? 'Inbox' : listCtrl.text.trim(),
            'repeat': when == null ? null : repeat,
            'dur': kind == 'task' ? null : mins,
            'allDay': date != null && time == null,
          };
          if (item == null) {
            final undo = <Rec>[];
            await s.addItem(
              kind: kind,
              title: name,
              when: when,
              est: kind == 'task' ? mins : null,
              undo: undo,
              extra: fields,
            );
            s.logAction('Added: $name', undo);
            s.save();
          } else {
            await s.updateRec('items', item, 'Edited: $name', (r) {
              r.addAll(fields);
              r['kind'] = kind;
              r['title'] = name;
              r['when'] = when;
              if (kind == 'task') r['est'] = mins;
              if (when != null) r['nid'] ??= s.nextId();
            });
          }
          if (ctx.mounted) Navigator.pop(ctx);
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: title,
                  autofocus: item == null,
                  style: const TextStyle(fontSize: 18),
                  decoration: const InputDecoration(hintText: 'What would you like to do?', border: InputBorder.none),
                ),
                TextField(
                  controller: desc,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(hintText: 'Description', border: InputBorder.none),
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'task', label: Text('Task')),
                    ButtonSegment(value: 'event', label: Text('Event')),
                    ButtonSegment(value: 'alarm', label: Text('Alarm')),
                  ],
                  selected: {kind},
                  onSelectionChanged: (v) => setS(() => kind = v.first),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.calendar_today, size: 18),
                      label: Text(date == null ? 'Date' : dayKey(date!)),
                      onPressed: pickDate,
                    ),
                    if (date != null)
                      InputChip(
                        avatar: const Icon(Icons.schedule, size: 18),
                        label: Text(time == null ? 'Start (all day)' : 'Start ${time!.format(ctx)}'),
                        onPressed: pickTime,
                        onDeleted: time == null ? null : () => setS(() => time = null),
                      ),
                    if (date != null && time != null)
                      InputChip(
                        avatar: const Icon(Icons.schedule_outlined, size: 18),
                        label: Text(endTime() == null ? 'End' : 'End ${endTime()!.format(ctx)}'),
                        onPressed: pickEnd,
                        onDeleted: endTime() == null ? null : () => setS(() => minutes.text = ''),
                      ),
                    if (date != null)
                      IconButton(
                        tooltip: 'Clear date',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setS(() {
                          date = null;
                          time = null;
                        }),
                      ),
                    if (date != null)
                      DropdownButton<String?>(
                        value: repeat,
                        items: [
                          for (final e in repeatNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                        ],
                        onChanged: (v) => setS(() => repeat = v),
                      ),
                    PopupMenuButton<int>(
                      tooltip: 'Priority',
                      initialValue: priority,
                      onSelected: (v) => setS(() => priority = v),
                      itemBuilder: (_) => [
                        for (var i = 3; i >= 0; i--)
                          PopupMenuItem(
                            value: i,
                            child: Row(
                              children: [
                                Icon(Icons.flag, color: priorityColors[i]),
                                const SizedBox(width: 8),
                                Text(priorityNames[i]),
                              ],
                            ),
                          ),
                      ],
                      child: Chip(
                        avatar: Icon(Icons.flag, color: priorityColors[priority], size: 18),
                        label: Text(priorityNames[priority]),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: tags,
                        decoration: const InputDecoration(labelText: 'Tags, comma separated', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: minutes,
                        onChanged: (_) => setS(() {}),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: kind == 'task' ? 'Estimate' : 'Duration',
                          isDense: true,
                        ),
                      ),
                    ),
                    DropdownButton<String>(
                      value: unit,
                      items: const [
                        DropdownMenuItem(value: 'min', child: Text('min')),
                        DropdownMenuItem(value: 'h', child: Text('hours')),
                      ],
                      onChanged: (v) => setS(() => unit = v ?? unit),
                    ),
                  ],
                ),
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: listCtrl.text),
                  optionsBuilder: (v) => allLists(s).where((l) => l.toLowerCase().contains(v.text.toLowerCase())),
                  onSelected: (v) => listCtrl.text = v,
                  fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
                    controller: ctrl,
                    focusNode: focus,
                    onChanged: (v) => listCtrl.text = v,
                    decoration: const InputDecoration(labelText: 'List', isDense: true),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (item != null)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                        onPressed: () {
                          Haptics.warn();
                          s.removeRec('items', item, 'Deleted: ${item['title']}');
                          Navigator.pop(ctx);
                        },
                      ),
                    const Spacer(),
                    FilledButton(onPressed: save, child: Text(item == null ? 'Add' : 'Save')),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
