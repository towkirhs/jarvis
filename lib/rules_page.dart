import 'package:flutter/material.dart';

import 'haptics.dart';
import 'rules.dart';
import 'store.dart';

/// "When this happens, if that is true, do this": the built-in links between Jarvis's parts (each with
/// its own switch) and your own rules. Every time a rule acts it shows up here and in Activity, with Undo.
class RulesPage extends StatelessWidget {
  const RulesPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Rules and links')),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('Rule'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RuleEditor(store: store))),
        ),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final scheme = Theme.of(context).colorScheme;
            final tt = Theme.of(context).textTheme;
            final rules = store.list('rules');
            final builtin = rules.where((r) => r['builtin'] != null).toList();
            final mine = rules.where((r) => r['builtin'] == null).toList()
              ..sort((a, b) => (a['on'] == true ? 0 : 1).compareTo(b['on'] == true ? 0 : 1));
            final recent = store.list('actions').reversed.where((a) => '${a['desc']}'.startsWith('Rule ')).take(8).toList();
            String desc(Rec r) => Rules.describe(r, money: store.money);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Text('Links', style: tt.titleMedium),
                Text('One thing you record updates another. Each is off until you switch it on; tap one to change its account.',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                for (final r in builtin)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${r['name']}'),
                    subtitle: Text(desc(r)),
                    value: r['on'] == true,
                    onChanged: (on) {
                      Haptics.toggle(on);
                      store.updateRec('rules', r, '${on ? 'Turned on' : 'Turned off'}: ${r['name']}', (x) => x['on'] = on);
                    },
                    secondary: IconButton(
                      tooltip: 'Change',
                      icon: const Icon(Icons.tune),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RuleEditor(store: store, rule: r))),
                    ),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.local_fire_department_outlined),
                  title: const Text('Habits on the calendar'),
                  subtitle: const Text('Set for each habit: open it and switch on "Add to my calendar when I tick it". '
                      'Calendar events and done tasks also tick habits whose link words they match.'),
                ),
                const SizedBox(height: 16),
                Text('Your rules', style: tt.titleMedium),
                if (mine.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'None yet. Tap Rule, or just tell Jarvis: "remind me to buy Duaris cream when I next get income in Cash, '
                      'if Cash has 500", or "every time I finish gym, log Walk".',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                for (final r in mine)
                  Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RuleEditor(store: store, rule: r))),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${r['name']}', style: tt.titleSmall),
                              const SizedBox(height: 2),
                              Text(desc(r)),
                              if ((r['fired'] as num? ?? 0) > 0)
                                Text('Done ${r['fired']} time${r['fired'] == 1 ? '' : 's'}, last ${niceWhen(r['last'] as int)}',
                                    style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                            ]),
                          ),
                          Switch(
                            value: r['on'] == true,
                            onChanged: (on) {
                              Haptics.toggle(on);
                              store.updateRec('rules', r, '${on ? 'Turned on' : 'Turned off'}: ${r['name']}', (x) => x['on'] = on);
                            },
                          ),
                        ]),
                      ),
                    ),
                  ),
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('What rules did lately', style: tt.titleMedium),
                  for (final a in recent)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text('${a['desc']}'.substring(5)),
                      subtitle: Text(niceWhen(a['ts'] as int)),
                      trailing: a['undone'] == true
                          ? const Text('Undone')
                          : TextButton(onPressed: () => store.undo(a['id'] as int), child: const Text('Undo')),
                    ),
                ],
              ],
            );
          },
        ),
      );
}

/// Makes or changes one rule: what sets it off, the conditions, and what it does.
class RuleEditor extends StatefulWidget {
  const RuleEditor({super.key, required this.store, this.rule});
  final Store store;
  final Rec? rule;

  @override
  State<RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<RuleEditor> {
  Store get s => widget.store;
  late final Map<String, dynamic> _r = widget.rule == null
      ? {'name': '', 'on': true, 'once': false, 'when': {'on': 'money'}, 'if': <dynamic>[], 'then': <dynamic>[{'do': 'remind', 'text': ''}]}
      : copyRec(widget.rule!);
  late final _name = TextEditingController(text: '${_r['name'] ?? ''}');

  Map get _when => _r['when'] as Map;
  List get _ifs => _r['if'] as List? ?? (_r['if'] = <dynamic>[]);
  List get _thens => _r['then'] as List? ?? (_r['then'] = <dynamic>[]);
  bool get _builtin => _r['builtin'] != null;

  List<String> get _accounts => [for (final a in s.list('accounts')) '${a['name']}'];
  List<String> get _habits => [for (final h in s.list('habits')) if (h['archived'] != true) '${h['name']}'];

  void _set(Map m, String key, Object? v) => setState(() => v == null || (v is String && v.trim().isEmpty) ? m.remove(key) : m[key] = v);

  Future<void> _save() async {
    final name = _name.text.trim();
    if (_thens.isEmpty) {
      Haptics.reject();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one thing for the rule to do.')));
      return;
    }
    _r['name'] = name.isEmpty ? 'Rule' : name;
    final old = widget.rule;
    if (old == null) {
      final rec = {'id': s.nextId(), ..._r};
      s.list('rules').add(rec);
      s.logAction('New rule: ${rec['name']}', [{'op': 'rm', 'col': 'rules', 'id': rec['id']}]);
      s.save();
    } else {
      await s.updateRec('rules', old, 'Changed rule: ${_r['name']}', (x) {
        x
          ..clear()
          ..addAll({..._r, 'id': old['id']});
      });
    }
    Haptics.success();
    if (mounted) Navigator.pop(context);
  }

  Widget _text(String label, Map m, String key, {bool number = false}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextFormField(
          initialValue: m[key] == null ? '' : '${m[key]}',
          keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
          decoration: InputDecoration(labelText: label),
          onChanged: (v) => _set(m, key, number ? num.tryParse(v.trim()) : v),
        ),
      );

  Widget _pick(String label, Map m, String key, List<String> options, {String any = 'Any'}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: DropdownButtonFormField<String?>(
          initialValue: options.contains(m[key]) ? m[key] as String : null,
          decoration: InputDecoration(labelText: label),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(any)),
            for (final o in options) DropdownMenuItem<String?>(value: o, child: Text(o)),
          ],
          onChanged: (v) => _set(m, key, v),
        ),
      );

  Widget _chips(Map m, String key, Map<Object?, String> options) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(spacing: 8, children: [
          for (final e in options.entries)
            ChoiceChip(label: Text(e.value), selected: m[key] == e.key, onSelected: (_) => _set(m, key, e.key)),
        ]),
      );

  Widget _days(Map m) {
    final days = ((m['days'] as List?) ?? const []).map((e) => (e as num).toInt()).toSet();
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 6, children: [
        for (var d = 1; d <= 7; d++)
          FilterChip(
            label: Text(names[d - 1]),
            selected: days.contains(d),
            onSelected: (on) => setState(() {
              on ? days.add(d) : days.remove(d);
              m['days'] = (days.toList()..sort());
            }),
          ),
      ]),
    );
  }

  Widget _time(String label, Map m, String key) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: OutlinedButton.icon(
          icon: const Icon(Icons.schedule),
          label: Text(m[key] == null ? label : '$label ${m[key]}'),
          onPressed: () async {
            final p = '${m[key] ?? '09:00'}'.split(':');
            final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.tryParse(p[0]) ?? 9, minute: int.tryParse(p.last) ?? 0));
            if (t != null) _set(m, key, '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
          },
        ),
      );

  List<Widget> _whenFields() {
    final w = _when;
    return switch (w['on']) {
      'money' => [
          _chips(w, 'moneyType', {null: 'Any', 'income': 'Income', 'expense': 'Spending', 'transfer': 'Transfer'}),
          _pick('Account', w, 'account', _accounts),
          _text('Category (any when empty)', w, 'category'),
          _text('At least this amount (any when empty)', w, 'min', number: true),
        ],
      'task_done' || 'event_end' => [_text('Title has these words (any when empty)', w, 'text')],
      'item' => [
          _chips(w, 'kind', {null: 'Anything', 'task': 'Task', 'event': 'Event', 'alarm': 'Alarm'}),
          _text('Title has these words (any when empty)', w, 'text'),
        ],
      'habit' => [_pick('Habit', w, 'habit', _habits, any: 'Any habit')],
      'loan' => [
          _chips(w, 'loanType', {null: 'Either', 'gave': 'I give', 'took': 'I take'}),
          _text('Person has these words (anyone when empty)', w, 'text'),
        ],
      'rent' => [_text('Room (any when empty)', w, 'text')],
      'time' => [_time('At', w, 'at'), _days(w)],
      _ => const [],
    };
  }

  Widget _part({required String title, required List<Widget> children, required VoidCallback onRemove}) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
              IconButton(tooltip: 'Remove', icon: const Icon(Icons.close), onPressed: onRemove),
            ]),
            Padding(padding: const EdgeInsets.only(right: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
          ]),
        ),
      );

  List<Widget> _ifFields(Map c) => switch (c['check']) {
        'balance' || 'spent' => [
            if (c['check'] == 'balance') _pick('Account', c, 'account', _accounts, any: 'Cash'),
            if (c['check'] == 'spent') ...[
              _text('Category (all spending when empty)', c, 'category'),
              _chips(c, 'period', {'day': 'Today', 'week': 'This week', null: 'This month'}),
            ],
            _text('At least', c, 'atLeast', number: true),
            _text('Or under', c, 'below', number: true),
          ],
        'days' => [_days(c)],
        'between' => [_time('From', c, 'from'), _time('To', c, 'to')],
        'habit_done' => [
            _pick('Habit', c, 'habit', _habits, any: 'Choose'),
            _chips(c, 'not', {null: 'Done today', true: 'Not done today'}),
          ],
        'task_open' => [
            _text('Task title has these words', c, 'text'),
            _chips(c, 'not', {null: 'Still open', true: 'Not open'}),
          ],
        _ => const [],
      };

  List<Widget> _thenFields(Map a) => switch (a['do']) {
        'remind' => [_text('Reminder', a, 'text')],
        'task' => [
            _text('Task', a, 'title'),
            _chips(a, 'day', {null: 'Today', 1: 'Tomorrow', 3: 'In 3 days', 7: 'In a week'}),
            _time('At', a, 'time'),
          ],
        'done' => [_text('Words of the open task to tick off', a, 'text')],
        'habit' => [_pick('Habit', a, 'habit', _habits, any: 'Choose')],
        'money' => [
            _chips(a, 'moneyType', {'income': 'Income', null: 'Spending'}),
            _text('Amount (the same amount when empty)', a, 'amount', number: true),
            _pick('Account', a, 'account', _accounts, any: 'Cash'),
            _text('Category', a, 'category'),
            _text('Note', a, 'note'),
          ],
        _ => const [],
      };

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rule == null ? 'New rule' : (_builtin ? '${_r['name']}' : 'Rule')),
        actions: [
          if (widget.rule != null && !_builtin)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                s.removeRec('rules', widget.rule!, 'Deleted rule: ${widget.rule!['name']}');
                Navigator.pop(context);
              },
            ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (!_builtin) TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(Rules.describe({..._r, 'name': _name.text}, money: s.money), style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 16),
          Text('When', style: tt.titleMedium),
          if (_builtin)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(Rules.triggers[_when['on']] ?? ''))
          else
            DropdownButtonFormField<String>(
              initialValue: _when['on'] as String?,
              items: [for (final e in Rules.triggers.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _r['when'] = {'on': v}),
            ),
          if (!_builtin) ..._whenFields(),
          const SizedBox(height: 20),
          Text('Only if', style: tt.titleMedium),
          if (_ifs.isEmpty) Text('Always (no conditions).', style: TextStyle(color: scheme.onSurfaceVariant)),
          for (final c in _ifs.cast<Map>())
            _part(title: Rules.checks[c['check']] ?? '?', children: _ifFields(c), onRemove: () => setState(() => _ifs.remove(c))),
          Align(
            alignment: Alignment.centerLeft,
            child: PopupMenuButton<String>(
              onSelected: (v) => setState(() => _ifs.add(<String, dynamic>{'check': v})),
              itemBuilder: (_) => [for (final e in Rules.checks.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
              child: const Padding(padding: EdgeInsets.all(8), child: Text('+ Add a condition')),
            ),
          ),
          const SizedBox(height: 12),
          Text('Then', style: tt.titleMedium),
          for (final a in _thens.cast<Map>())
            _part(title: Rules.actions[a['do']] ?? '?', children: _thenFields(a), onRemove: () => setState(() => _thens.remove(a))),
          Align(
            alignment: Alignment.centerLeft,
            child: PopupMenuButton<String>(
              onSelected: (v) => setState(() => _thens.add(<String, dynamic>{'do': v})),
              itemBuilder: (_) => [for (final e in Rules.actions.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
              child: const Padding(padding: EdgeInsets.all(8), child: Text('+ Add something to do')),
            ),
          ),
          Text('Texts can use {amount}, {title}, {account}, {category}, {person} from what set the rule off.',
              style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          if (!_builtin)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Only the next time'),
              subtitle: const Text('Turns itself off after it acts once'),
              value: _r['once'] == true,
              onChanged: (on) => setState(() => _r['once'] = on),
            ),
        ],
      ),
    );
  }
}
