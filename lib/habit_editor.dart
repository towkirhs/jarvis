import 'package:flutter/material.dart';

import 'habit_core.dart';
import 'habit_stats.dart';
import 'habit_widgets.dart';
import 'haptics.dart';
import 'store.dart';

/// Creates a habit, or edits [habit] when given. Returns the habit, or null if cancelled.
Future<Rec?> showAddHabit(BuildContext context, Store store, {String name = '', Rec? habit}) =>
    Navigator.push<Rec>(context, MaterialPageRoute(builder: (_) => HabitEditor(store: store, habit: habit, name: name)));

class HabitEditor extends StatefulWidget {
  const HabitEditor({super.key, required this.store, this.habit, this.name = ''});
  final Store store;
  final Rec? habit;
  final String name;

  @override
  State<HabitEditor> createState() => _HabitEditorState();
}

class _HabitEditorState extends State<HabitEditor> {
  Store get s => widget.store;
  Rec? get old => widget.habit;

  late final _name = TextEditingController(text: (old?['name'] as String?) ?? widget.name);
  late String _type = (old?['type'] as String?) ?? 'yesno';
  late final _target = TextEditingController(text: _initTarget());
  late final _unit = TextEditingController(text: (old?['unit'] as String?) ?? '');
  late int _scale = ((old?['scale'] as num?) ?? 10).round();
  late String? _by = old?['by'] as String?;
  late final List<TextEditingController> _steps = [
    for (final i in ((old?['items'] as List?) ?? const []).cast<String>()) TextEditingController(text: i),
  ];
  late String _goal = (old?['goal'] as String?) ?? 'build';
  late Map<String, dynamic> _sched = old == null ? {'kind': 'daily'} : Map.of(HabitCore.sched(old!));
  late int _grace = (old?['grace'] as int?) ?? 0;
  late bool _progOn = old?['prog'] != null;
  late final _progBy = TextEditingController(text: _num((old?['prog'] as Map?)?['by']));
  late final _progEvery = TextEditingController(text: _num((old?['prog'] as Map?)?['every'] ?? 7));
  late final _progMax = TextEditingController(text: _num((old?['prog'] as Map?)?['max']));
  late String _routine = (old?['routine'] as String?) ?? '';
  late final _customRoutine = TextEditingController(
    text: const ['', 'morning', 'evening'].contains(_routine) ? '' : _routine,
  );
  late int? _after = old?['after'] as int?;
  late String? _remind = old?['remind'] as String?;
  late bool _toCal = old?['toCal'] == true;
  late final _link = TextEditingController(text: ((old?['link'] as List?) ?? const []).join(', '));
  late int _color = (old?['color'] as int?) ?? s.list('habits').length;
  late String? _icon = old?['icon'] as String?;
  String? _error;

  static String _num(Object? v) => v == null ? '' : fmtNum(v as num);

  String _initTarget() {
    final h = old;
    if (h == null) return _num(HabitType.all.first.target);
    return _num(HabitCore.target({...h, 'prog': null}, DateTime.now()) ?? h['target']);
  }

  bool get _measured => !const ['yesno', 'time', 'checklist', 'auto'].contains(_type);

  void _pickType(HabitType t) {
    if (!t.ready) return;
    setState(() {
      _type = t.key;
      if (old == null || old!['type'] != t.key) {
        _target.text = _num(t.target);
        _unit.text = t.unit ?? '';
        if (t.key == 'limit' && _goal == 'build') _goal = 'reduce';
        if (t.key == 'checklist' && _steps.isEmpty) _steps.addAll([TextEditingController(), TextEditingController()]);
      }
    });
  }

  Future<void> _save() async {
    final n = _name.text.trim();
    if (n.isEmpty) return setState(() => _error = Haptics.rejected() ?? 'Give the habit a name.');
    final target = num.tryParse(_target.text.trim().replaceAll(',', '.'));
    if (_measured && (target == null || target <= 0)) return setState(() => _error = Haptics.rejected() ?? 'Set a target above 0.');
    if (_type == 'time' && _by == null) return setState(() => _error = Haptics.rejected() ?? 'Pick the time it should be done by.');
    final steps = [for (final c in _steps) c.text.trim()]..removeWhere((x) => x.isEmpty);
    if (_type == 'checklist' && steps.isEmpty) return setState(() => _error = Haptics.rejected() ?? 'Add at least one step.');
    if (_sched['kind'] == 'days' && ((_sched['days'] as List?) ?? const []).isEmpty) {
      return setState(() => _error = Haptics.rejected() ?? 'Pick at least one day.');
    }
    final routine = _routine == 'custom' ? _customRoutine.text.trim() : _routine;
    final today = dayKey(DateTime.now());

    void apply(Rec r) {
      r['name'] = n;
      r['type'] = _type;
      // A new target applies from today; old days keep the target they had.
      if (_measured) {
        final before = old == null ? null : HabitCore.target({...old!, 'prog': null}, DateTime.now());
        if (r['target'] == null) {
          r['target'] = target;
        } else if (before != target) {
          final history = ((r['targets'] as List?) ?? []).cast<Map>().where((e) => e['from'] != today).toList()
            ..add({'from': today, 'v': target});
          r['targets'] = history;
        }
      }
      r['unit'] = _measured ? _unit.text.trim() : null;
      r['scale'] = _type == 'rating' ? _scale : null;
      r['by'] = _type == 'time' ? _by : null;
      r['items'] = _type == 'checklist' ? steps : null;
      r['goal'] = _goal;
      r['sched'] = _sched;
      // Keep the old fields roughly right for anything that still reads them.
      r['times'] = switch (_sched['kind']) { 'week' || 'month' => _sched['n'], 'daily' => 7, _ => 1 };
      r['per'] = _sched['kind'] == 'month' ? 'month' : 'week';
      r['grace'] = _grace;
      r['prog'] = _progOn && _measured
          ? {
              'by': num.tryParse(_progBy.text.trim()) ?? 1,
              'every': int.tryParse(_progEvery.text.trim()) ?? 7,
              if (num.tryParse(_progMax.text.trim()) != null) 'max': num.parse(_progMax.text.trim()),
            }
          : null;
      r['routine'] = routine.isEmpty ? null : routine;
      r['after'] = _after;
      final link = [for (final w in _link.text.split(',')) if (w.trim().isNotEmpty) w.trim().toLowerCase()];
      r['link'] = link.isEmpty ? null : link;
      r['toCal'] = _toCal ? true : null;
      r['remind'] = _remind;
      if (_remind != null) r['rid'] ??= s.nextId();
      r['color'] = _color;
      r['icon'] = _icon;
    }

    Haptics.tap();
    if (old == null) {
      final h = await s.addHabit(n, 7, remind: _remind);
      apply(h);
      h['start'] = today;
      s.save();
      if (mounted) Navigator.pop(context, h);
      return;
    }
    await s.updateRec('habits', old!, 'Edited habit $n', apply);
    if (mounted) Navigator.pop(context, old);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(t, style: tt.titleSmall),
        );
    final others = s.list('habits').where((h) => h['id'] != old?['id'] && h['archived'] != true).toList();
    final kind = _sched['kind'] as String;
    return Scaffold(
      appBar: AppBar(
        title: Text(old == null ? 'New habit' : 'Edit habit'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          TextField(
            controller: _name,
            autofocus: old == null && widget.name.isEmpty,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name, like Drink water'),
          ),
          label('How do you measure it?'),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.25,
            children: [
              for (final t in HabitType.all)
                _TypeTile(type: t, selected: _type == t.key, onTap: () => _pickType(t)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(HabitType.all.firstWhere((t) => t.key == _type).hint,
                style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          if (_measured) ...[
            label(_type == 'limit' ? 'Most allowed a day' : (_type == 'rating' ? 'A good rating is at least' : 'Daily target')),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _target,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
              ),
              if (_type != 'rating' && _type != 'percent') ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _type == 'duration'
                      ? const InputDecorator(decoration: InputDecoration(labelText: 'Unit'), child: Text('minutes'))
                      : TextField(controller: _unit, decoration: const InputDecoration(labelText: 'Unit, like L or km')),
                ),
              ],
            ]),
            if (_type == 'rating') ...[
              label('Scale'),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 5, label: Text('1 to 5')),
                  ButtonSegment(value: 10, label: Text('1 to 10')),
                ],
                selected: {_scale},
                onSelectionChanged: (v) => setState(() => _scale = v.first),
              ),
            ],
          ],
          if (_type == 'time') ...[
            label('Done by'),
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule),
              label: Text(_by == null ? 'Pick a time' : time12(_by!)),
              onPressed: () async {
                final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 6, minute: 0));
                if (t != null) setState(() => _by = '${two(t.hour)}:${two(t.minute)}');
              },
            ),
          ],
          if (_type == 'checklist') ...[
            label('Steps'),
            for (var i = 0; i < _steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(child: TextField(controller: _steps[i], decoration: InputDecoration(labelText: 'Step ${i + 1}'))),
                  IconButton(
                    tooltip: 'Remove step',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _steps.removeAt(i)),
                  ),
                ]),
              ),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add step'),
              onPressed: () => setState(() => _steps.add(TextEditingController())),
            ),
          ],
          label('Goal'),
          DropdownButtonFormField<String>(
            initialValue: _goal,
            items: [for (final e in goals.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _goal = v ?? _goal),
          ),
          label('When'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (k, l) in const [
              ('daily', 'Every day'),
              ('days', 'Some weekdays'),
              ('week', 'Times a week'),
              ('month', 'Times a month'),
              ('every', 'Every few days'),
              ('once', 'Once'),
            ])
              ChoiceChip(
                label: Text(l),
                selected: kind == k,
                onSelected: (_) => setState(() => _sched = switch (k) {
                      'days' => {'kind': 'days', 'days': [1, 2, 3, 4, 5]},
                      'week' => {'kind': 'week', 'n': 3},
                      'month' => {'kind': 'month', 'n': 12},
                      'every' => {'kind': 'every', 'n': 2},
                      'once' => {'kind': 'once', 'date': dayKey(DateTime.now())},
                      _ => {'kind': 'daily'},
                    }),
              ),
          ]),
          const SizedBox(height: 12),
          if (kind == 'days')
            Wrap(spacing: 6, children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1]),
                  selected: ((_sched['days'] as List?) ?? const []).contains(d),
                  onSelected: (on) => setState(() {
                    final days = ((_sched['days'] as List?) ?? []).cast<int>().toList();
                    on ? days.add(d) : days.remove(d);
                    _sched = {'kind': 'days', 'days': days..sort()};
                  }),
                ),
            ]),
          if (kind == 'week' || kind == 'month' || kind == 'every')
            _Stepper(
              value: _sched['n'] as int,
              min: kind == 'every' ? 2 : 1,
              max: kind == 'week' ? 7 : (kind == 'month' ? 31 : 60),
              suffix: kind == 'every' ? 'days between' : (kind == 'week' ? 'times a week' : 'times a month'),
              onChanged: (v) => setState(() => _sched = {..._sched, 'n': v}),
            ),
          if (kind == 'once')
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text('On ${_sched['date']}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: DateTime.parse(_sched['date'] as String),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _sched = {'kind': 'once', 'date': dayKey(d)});
              },
            ),
          if (kind != 'week' && kind != 'month' && kind != 'once') ...[
            label('Grace days'),
            Text('Missed days in a row that do not break your streak.',
                style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('None')),
                ButtonSegment(value: 1, label: Text('1')),
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 3, label: Text('3')),
              ],
              selected: {_grace},
              onSelectionChanged: (v) => setState(() => _grace = v.first),
            ),
          ],
          if (_measured && _type != 'rating' && _type != 'limit') ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Raise the target over time'),
              subtitle: const Text('Like 20 push-ups now, 5 more every week'),
              value: _progOn,
              onChanged: (v) {
                Haptics.toggle(v);
                setState(() => _progOn = v);
              },
            ),
            if (_progOn)
              Row(children: [
                Expanded(child: TextField(controller: _progBy, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Add'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _progEvery, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Every N days'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _progMax, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Up to'))),
              ]),
          ],
          label('Routine'),
          Wrap(spacing: 8, children: [
            for (final (k, l) in const [('', 'None'), ('morning', 'Morning'), ('evening', 'Evening'), ('custom', 'Other')])
              ChoiceChip(
                label: Text(l),
                selected: k == 'custom'
                    ? !const ['', 'morning', 'evening'].contains(_routine)
                    : _routine == k,
                onSelected: (_) => setState(() => _routine = k),
              ),
          ]),
          if (!const ['', 'morning', 'evening'].contains(_routine))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(controller: _customRoutine, decoration: const InputDecoration(labelText: 'Routine name, like After class')),
            ),
          if (others.isNotEmpty) ...[
            label('Do it after (habit stacking)'),
            DropdownButtonFormField<int?>(
              initialValue: others.any((h) => h['id'] == _after) ? _after : null,
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Not stacked')),
                for (final h in others) DropdownMenuItem<int?>(value: h['id'] as int, child: Text(h['name'] as String)),
              ],
              onChanged: (v) => setState(() => _after = v),
            ),
          ],
          label('Calendar'),
          TextField(
            controller: _link,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Words in event or task titles', hintText: 'tuition, class'),
          ),
          const SizedBox(height: 6),
          Text(
            switch (_type) {
              'duration' || 'limit' => 'A finished event with one of these words adds its minutes. Sleep 2 am to 6 am adds 4 hours.',
              'count' || 'frequency' => 'Each finished event or done task with one of these words counts once.',
              'time' => 'The time the event ends counts, so the end of "Sleep" is when you got up.',
              _ => 'A finished event or done task with one of these words marks the day done.',
            },
            style: tt.bodySmall,
          ),
          if (_link.text.trim().isEmpty && _name.text.trim().isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _link.text = _name.text.trim().toLowerCase()),
                child: Text('Use "${_name.text.trim().toLowerCase()}"'),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Add to my calendar when I tick it'),
            subtitle: Text(_type == 'duration' ? 'A block as long as the minutes you log' : 'A 30 minute block ending when you tick it'),
            value: _toCal,
            onChanged: (on) {
              Haptics.toggle(on);
              setState(() => _toCal = on);
            },
          ),
          label('Reminder'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_remind == null ? 'No reminder' : 'Every day at ${time12(_remind!)}'),
            value: _remind != null,
            onChanged: (on) async {
                Haptics.toggle(on);
              if (!on) return setState(() => _remind = null);
              final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 20, minute: 0));
              if (t != null) setState(() => _remind = '${two(t.hour)}:${two(t.minute)}');
            },
          ),
          label('Look'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < habitColors.length; i++)
              GestureDetector(
                onTap: () => setState(() => _color = i),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Color(habitColors[i]),
                  child: _color % habitColors.length == i ? const Icon(Icons.check, size: 18, color: Colors.black) : null,
                ),
              ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final e in habitIcons.entries)
              IconButton(
                tooltip: e.key,
                isSelected: _icon == e.key,
                style: IconButton.styleFrom(
                  backgroundColor: _icon == e.key ? Color(habitColors[_color % habitColors.length]) : null,
                ),
                icon: Icon(e.value, color: _icon == e.key ? Colors.black : null),
                onPressed: () => setState(() => _icon = _icon == e.key ? null : e.key),
              ),
          ]),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: Text(old == null ? 'Add habit' : 'Save changes')),
        ],
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({required this.type, required this.selected, required this.onTap});
  final HabitType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = !type.ready ? scheme.outline : (selected ? scheme.onPrimaryContainer : scheme.onSurface);
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: type.ready ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(typeIcons[type.key], color: fg),
              const SizedBox(height: 8),
              Text(
                type.ready ? type.label : '${type.label}\n(coming)',
                textAlign: TextAlign.center,
                maxLines: 2,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.min, required this.max, required this.suffix, required this.onChanged});
  final int value, min, max;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(children: [
        IconButton(tooltip: 'Decrease', onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove)),
        Text('$value', style: Theme.of(context).textTheme.titleMedium),
        IconButton(tooltip: 'Increase', onPressed: value < max ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add)),
        Text(suffix),
      ]);
}
