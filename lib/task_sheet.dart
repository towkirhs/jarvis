import 'package:flutter/material.dart';

import 'cal_grid.dart' show onEventColor;
import 'clash.dart';
import 'clock.dart';
import 'haptics.dart';
import 'place_picker.dart';
import 'day_planner.dart';
import 'needs_editor.dart';
import 'store.dart';
import 'theme.dart' show accents;

const priorityNames = ['None', 'Low', 'Medium', 'High'];
const priorityColors = [Colors.grey, Colors.blue, Colors.orange, Colors.red];
const repeatNames = {null: 'No repeat', 'daily': 'Daily', 'weekly': 'Weekly', 'monthly': 'Monthly', 'yearly': 'Yearly'};

/// Names of all lists in use, Inbox first.
List<String> allLists(Store s) {
  final names = {'Inbox', for (final i in s.list('items')) (i['list'] as String?) ?? 'Inbox'};
  return names.toList();
}

/// Adds a task (or edits [item]) by hand, on a full page. [day], [at] and [newKind] preset a new one.
/// Only the name is needed; a task also says whether it takes time. Everything else is under "More options".
Future<void> showTaskSheet(BuildContext context, Store s, {Rec? item, DateTime? day, TimeOfDay? at, String? newKind, int? presetMinutes, String? presetTitle}) =>
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TaskFormPage(store: s, item: item, day: day, at: at, newKind: newKind, presetMinutes: presetMinutes, presetTitle: presetTitle),
      ),
    );

const _blockSizes = [0, 25, 45, 60, 90, 120, 180];

class TaskFormPage extends StatefulWidget {
  const TaskFormPage({super.key, required this.store, this.item, this.day, this.at, this.newKind, this.presetMinutes, this.presetTitle});
  final Store store;
  final Rec? item;
  final DateTime? day;
  final TimeOfDay? at;
  final String? newKind;
  final int? presetMinutes;
  final String? presetTitle;

  @override
  State<TaskFormPage> createState() => _TaskFormPageState();
}

class _TaskFormPageState extends State<TaskFormPage> {
  Store get s => widget.store;
  Rec? get item => widget.item;

  late final title = TextEditingController(text: item?['title'] as String? ?? widget.presetTitle ?? '');
  late final desc = TextEditingController(text: item?['desc'] as String? ?? '');
  late final location = TextEditingController(text: item?['location'] as String? ?? '');
  late final tags = TextEditingController(text: ((item?['tags'] as List?) ?? []).join(', '));
  late final listCtrl = TextEditingController(text: (item?['list'] as String?) ?? 'Inbox');
  late final TextEditingController minutes;
  late String? colorKey = item?['color'] as String?;
  // Days an all-day item covers, the first one included.
  late var span = ((item?['span'] as num?)?.toInt() ?? 1).clamp(1, 366).toInt();
  late var kind = (item?['kind'] as String?) ?? widget.newKind ?? 'task';
  late var priority = (item?['priority'] as int?) ?? 0;
  late var repeat = item?['repeat'] as String?;
  // A new event starts with your usual reminder (Settings); you can change it here.
  late var lead = item != null ? ((item!['lead'] as num?)?.toInt() ?? 0) : ((widget.newKind ?? 'task') == 'event' ? Lead.defaultFor(s.settings) : 0);
  var leadTouched = false;
  late int? placeId = item?['place'] as int?;
  late var placeWhen = (item?['placeWhen'] as String?) ?? 'arrive';
  DateTime? date;
  TimeOfDay? time;
  var unit = 'min';
  // Whether a task takes time (false: quick, no block). Null until you say, then Jarvis guesses from the title.
  late bool? quick = item?['quick'] as bool?;
  late var chunk = (item?['chunk'] as num?)?.toInt() ?? 0;
  late Object? needs = item?['needs'];
  late Object? doneIf = item?['doneIf'];
  late bool more;

  @override
  void initState() {
    super.initState();
    final w = item?['when'] as int?;
    date = w != null ? fromMs(w) : widget.day;
    time = w != null ? (item?['allDay'] == true ? null : TimeOfDay.fromDateTime(fromMs(w))) : widget.at;
    final old = item == null ? widget.presetMinutes : (kind == 'task' ? item!['est'] : item!['dur']);
    // Whole and half hours of an hour or more are shown in hours.
    unit = old is int && old >= 60 && old % 30 == 0 ? 'h' : 'min';
    minutes = TextEditingController(text: old == null ? '' : (unit == 'h' ? '${(old as int) / 60}'.replaceAll('.0', '') : '$old'));
    // An item that already uses the extra options opens with them showing.
    final i = item;
    more = i != null &&
        (desc.text.isNotEmpty || location.text.isNotEmpty || tags.text.isNotEmpty || priority > 0 || colorKey != null ||
            placeId != null || chunk > 0 || needs != null || doneIf != null || listCtrl.text != 'Inbox');
  }

  bool get _quick => kind == 'task' && (quick ?? (item == null ? false : DayPlanner.isQuick(item!)));

  int? get _minutes {
    final a = double.tryParse(minutes.text.trim());
    return a == null ? null : (unit == 'h' ? a * 60 : a).round();
  }

  TimeOfDay? get _end {
    final m = _minutes;
    if (time == null || m == null) return null;
    final total = time!.hour * 60 + time!.minute + m;
    return TimeOfDay(hour: (total ~/ 60) % 24, minute: total % 60);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: date ?? now, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 5));
    if (d != null) setState(() => date = d);
  }

  Future<void> _pickLast() async {
    final first = DateTime(date!.year, date!.month, date!.day);
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(first.year, first.month, first.day + span - 1),
      firstDate: first,
      lastDate: DateTime(first.year + 5),
    );
    if (d != null) setState(() => span = DateTime(d.year, d.month, d.day).difference(first).inDays + 1);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: time ?? const TimeOfDay(hour: 9, minute: 0));
    if (t != null) setState(() => time = t);
  }

  // Picking an end time sets the length (shown in hours when it is whole or half hours).
  Future<void> _pickEnd() async {
    final start = time!;
    final t = await showTimePicker(context: context, initialTime: _end ?? TimeOfDay(hour: (start.hour + 1) % 24, minute: start.minute));
    if (t == null) return;
    var diff = (t.hour * 60 + t.minute) - (start.hour * 60 + start.minute);
    if (diff <= 0) diff += 24 * 60;
    setState(() {
      unit = diff >= 60 && diff % 30 == 0 ? 'h' : 'min';
      minutes.text = unit == 'h' ? '${diff / 60}'.replaceAll('.0', '') : '$diff';
    });
  }

  /// The map and your saved places: the place's name becomes the location.
  Future<void> _pickWhere() async {
    final id = await pickPlace(context, s, current: placeId);
    if (id == null || !mounted) return;
    setState(() {
      placeId = id;
      location.text = '${Clock.place(s.list('places'), id)?['name'] ?? location.text}';
    });
  }

  Future<void> _save() async {
    final name = title.text.trim();
    if (name.isEmpty) {
      Haptics.reject();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give it a name first.')));
      return;
    }
    int? when;
    if (date != null) {
      when = DateTime(date!.year, date!.month, date!.day, time?.hour ?? 9, time?.minute ?? 0).millisecondsSinceEpoch;
    }
    final mins = _quick ? null : _minutes;
    final isTask = kind == 'task';
    final fields = <String, dynamic>{
      'desc': desc.text.trim().isEmpty ? null : desc.text.trim(),
      'priority': priority,
      'tags': tags.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      'list': listCtrl.text.trim().isEmpty ? 'Inbox' : listCtrl.text.trim(),
      'repeat': when == null ? null : repeat,
      'lead': kind == 'alarm' || when == null || time == null ? 0 : lead,
      'dur': isTask ? null : mins,
      'allDay': date != null && time == null,
      'location': location.text.trim().isEmpty ? null : location.text.trim(),
      'color': colorKey,
      'span': date != null && time == null && !isTask && span > 1 ? span : null,
      'place': placeId,
      'placeWhen': placeId == null ? null : placeWhen,
      if (isTask && quick != null) 'quick': quick,
      'chunk': isTask && !_quick && chunk > 0 && (mins ?? 0) > chunk ? chunk : null,
      'needs': needs,
      'doneIf': isTask ? doneIf : null,
    };
    final old = item;
    if (old == null) {
      final undo = <Rec>[];
      await s.addItem(kind: kind, title: name, when: when, est: isTask ? mins : null, undo: undo, extra: fields);
      s.logAction('Added: $name', undo);
      s.save();
    } else {
      await s.updateRec('items', old, 'Edited: $name', (r) {
        r.addAll(fields);
        r['kind'] = kind;
        r['title'] = name;
        r['when'] = when;
        if (isTask) r['est'] = mins;
        if (when != null) r['nid'] ??= s.nextId();
      });
    }
    Haptics.success();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    if (placeId != null && !await ensureLocation(messenger.context)) {
      messenger.showSnackBar(const SnackBar(content: Text('Saved. It needs location "Allow all the time" to remind you at the place.')));
    }
    await Clock.sync(s);
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _whenChips() => Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          InputChip(
            avatar: const Icon(Icons.calendar_today, size: 18),
            label: Text(date == null ? 'Date' : niceDay(DateTime(date!.year, date!.month, date!.day).millisecondsSinceEpoch)),
            onPressed: _pickDate,
            onDeleted: date == null
                ? null
                : () => setState(() {
                      date = null;
                      time = null;
                    }),
          ),
          if (date != null)
            InputChip(
              avatar: const Icon(Icons.schedule, size: 18),
              label: Text(time == null ? 'Start time' : 'Start ${time!.format(context)}'),
              onPressed: _pickTime,
              onDeleted: time == null ? null : () => setState(() => time = null),
            ),
          if (date != null && time != null && !_quick)
            InputChip(
              avatar: const Icon(Icons.schedule_outlined, size: 18),
              label: Text(_end == null ? 'End time' : 'End ${_end!.format(context)}'),
              onPressed: _pickEnd,
              onDeleted: _end == null ? null : () => setState(() => minutes.text = ''),
            ),
          if (date != null && time == null && kind == 'event')
            InputChip(
              avatar: const Icon(Icons.event_available_outlined, size: 18),
              label: Text(span > 1 ? 'Until ${niceDay(DateTime(date!.year, date!.month, date!.day + span - 1).millisecondsSinceEpoch)}' : 'End date'),
              onPressed: _pickLast,
              onDeleted: span > 1 ? () => setState(() => span = 1) : null,
            ),
          if (date != null && time != null && kind != 'alarm')
            PopupMenuButton<int>(
              tooltip: 'Remind me',
              initialValue: lead,
              onSelected: (v) => setState(() {
                lead = v;
                leadTouched = true;
              }),
              itemBuilder: (_) => [for (final m in Lead.options) PopupMenuItem(value: m, child: Text(Lead.name(m)))],
              child: Chip(avatar: const Icon(Icons.notifications_none, size: 18), label: Text(Lead.name(lead))),
            ),
          if (date != null)
            PopupMenuButton<String?>(
              tooltip: 'Repeat',
              onSelected: (v) => setState(() => repeat = v == '' ? null : v),
              itemBuilder: (_) => [for (final e in repeatNames.entries) PopupMenuItem(value: e.key ?? '', child: Text(e.value))],
              child: Chip(avatar: const Icon(Icons.repeat, size: 18), label: Text(repeatNames[repeat]!)),
            ),
        ],
      );

  Widget _length() => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextField(
            controller: minutes,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: kind == 'task' ? 'How long it takes' : 'How long it lasts'),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 132,
          child: DropdownButtonFormField<String>(
            initialValue: unit,
            decoration: const InputDecoration(labelText: 'In'),
            items: const [DropdownMenuItem(value: 'min', child: Text('minutes')), DropdownMenuItem(value: 'h', child: Text('hours'))],
            onChanged: (v) => setState(() => unit = v ?? unit),
          ),
        ),
      ]);

  List<Widget> _moreOptions(ColorScheme scheme) => [
        _title('Details'),
        TextField(controller: desc, maxLines: 4, minLines: 1, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Notes')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: location,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Location', prefixIcon: Icon(Icons.place_outlined)),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(tooltip: 'Pick on the map', icon: const Icon(Icons.map_outlined), onPressed: _pickWhere),
        ]),
        if (placeId != null) ...[
          const SizedBox(height: 8),
          Text('Remind me there', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'arrive', label: Text('When I arrive')),
              ButtonSegment(value: 'leave', label: Text('When I leave')),
              ButtonSegment(value: 'off', label: Text('Off')),
            ],
            selected: {placeWhen},
            onSelectionChanged: (v) => setState(() => v.first == 'off' ? placeId = null : placeWhen = v.first),
          ),
        ],
        _title('Importance'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var p = 0; p <= 3; p++)
            ChoiceChip(
              avatar: Icon(Icons.flag, size: 18, color: priorityColors[p]),
              showCheckmark: false,
              label: Text(priorityNames[p]),
              selected: priority == p,
              onSelected: (_) => setState(() => priority = p),
            ),
        ]),
        if (kind != 'alarm') ...[
          _title('Colour'),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final key in <String?>[null, ...accents.keys.where((k) => k != 'default')])
              InkResponse(
                radius: 24,
                onTap: () => setState(() => colorKey = key),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: key == null ? scheme.surfaceContainerHighest : accents[key],
                  child: colorKey == key
                      ? Icon(Icons.check, size: 18, color: key == null ? scheme.onSurface : onEventColor(accents[key]!))
                      : (key == null ? Icon(Icons.format_color_reset, size: 16, color: scheme.onSurfaceVariant) : null),
                ),
              ),
          ]),
        ],
        _title('Sort it'),
        Autocomplete<String>(
          initialValue: TextEditingValue(text: listCtrl.text),
          optionsBuilder: (v) => allLists(s).where((l) => l.toLowerCase().contains(v.text.toLowerCase())),
          onSelected: (v) => listCtrl.text = v,
          fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
            controller: ctrl,
            focusNode: focus,
            onChanged: (v) => listCtrl.text = v,
            decoration: const InputDecoration(labelText: 'List'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: tags, decoration: const InputDecoration(labelText: 'Tags, separated by commas')),
        if (kind == 'task' && !_quick) ...[
          _title('Do it in blocks'),
          Text('A long task can be split, like 8 hours as four 2 hour blocks. Plan my day places the blocks.',
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in _blockSizes)
              ChoiceChip(label: Text(m == 0 ? 'One go' : fmtMinutes(m)), selected: chunk == m, onSelected: (_) => setState(() => chunk = m)),
          ]),
        ],
        _title('Only if'),
        Text('Link it to another task or habit, to money, or to a countdown. It stays quiet until that is true.',
            style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        NeedsEditor(store: s, needs: needs, self: item?['id'] as int?, onChanged: (v) => setState(() => needs = v)),
        if (kind == 'task') ...[
          _title('Counts as done when'),
          Text('Jarvis ticks it off by itself once this is true.', style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          NeedsEditor(store: s, needs: doneIf, self: item?['id'] as int?, onChanged: (v) => setState(() => doneIf = v)),
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String? clash;
    if (kind == 'event' && date != null && time != null) {
      final start = DateTime(date!.year, date!.month, date!.day, time!.hour, time!.minute).millisecondsSinceEpoch;
      clash = Clash.sentence(Clash.find(s.list('items'), start, _minutes ?? Clash.defaultMinutes, excludeId: item?['id'] as int?), clock);
      if (clash.isEmpty) clash = null;
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: Text(item == null ? 'New' : 'Edit'),
        actions: [
          if (item != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                Haptics.warn();
                s.removeRec('items', item!, 'Deleted: ${item!['title']}');
                Navigator.pop(context);
              },
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + MediaQuery.of(context).viewInsets.bottom),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _save,
            child: Text(item == null ? 'Add' : 'Save'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: title,
            autofocus: item == null,
            textCapitalization: TextCapitalization.sentences,
            style: Theme.of(context).textTheme.titleLarge,
            decoration: const InputDecoration(hintText: 'What do you need to do?'),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'task', label: Text('Task')),
              ButtonSegment(value: 'event', label: Text('Event')),
              ButtonSegment(value: 'alarm', label: Text('Alarm')),
            ],
            selected: {kind},
            onSelectionChanged: (v) => setState(() {
              kind = v.first;
              if (!leadTouched && item == null) lead = kind == 'event' ? Lead.defaultFor(s.settings) : 0;
            }),
          ),
          if (kind == 'task') ...[
            _title('Does it take time?'),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.hourglass_empty), label: Text('Takes time')),
                ButtonSegment(value: true, icon: Icon(Icons.bolt), label: Text('Quick, no time')),
              ],
              selected: {_quick},
              onSelectionChanged: (v) => setState(() => quick = v.first),
            ),
          ],
          if (!_quick && kind != 'alarm') ...[
            const SizedBox(height: 12),
            _length(),
          ],
          _title('When'),
          _whenChips(),
          if (clash != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: scheme.tertiary),
                const SizedBox(width: 8),
                Expanded(child: Text(clash, style: TextStyle(color: scheme.tertiary))),
              ]),
            ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: Icon(more ? Icons.expand_less : Icons.expand_more),
              label: Text(more ? 'Fewer options' : 'More options'),
              onPressed: () => setState(() => more = !more),
            ),
          ),
          if (more) ..._moreOptions(scheme),
        ],
      ),
    );
  }
}
