import 'package:flutter/material.dart';

import 'haptics.dart';
import 'loans.dart';
import 'store.dart';

String _when(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.day} ${m[d.month - 1]} ${d.year}, $h:${two(d.minute)} ${d.hour < 12 ? 'am' : 'pm'}';
}

const _rangeNames = {'all': 'All time', 'today': 'Today', 'week': 'This week', 'month': 'This month'};

List<Map<String, dynamic>> _txs(Store s) => s.list('loans').cast<Map<String, dynamic>>();

/// What one person owes me (positive) or I owe them (negative), in words.
String _owes(Store s, num b) => b > 0 ? 'to receive ${s.money(b)}' : (b < 0 ? 'to pay ${s.money(-b)}' : 'settled');

/// People I lent to or borrowed from, what is owed each way, and the latest transactions.
class LoansPage extends StatelessWidget {
  const LoansPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final s = store;
          final scheme = Theme.of(context).colorScheme;
          final tt = Theme.of(context).textTheme;
          final people = s.list('loanPeople').toList()
            ..sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
          final txs = _txs(s);
          final t = Loans.totals([for (final p in people) p['id'] as int], txs);
          Widget tile(String label, num v, String sub, Color color) => Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: tt.labelLarge),
                      const SizedBox(height: 4),
                      Text(s.money(v), style: tt.headlineSmall?.copyWith(color: color)),
                      Text(sub, style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ]),
                  ),
                ),
              );
          return Scaffold(
            appBar: AppBar(
              title: const Text('Loans and debts'),
              actions: [
                IconButton(tooltip: 'Add a person', icon: const Icon(Icons.person_add_alt_1_outlined), onPressed: () => editLoanPerson(context, s, null)),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => editLoanTx(context, s),
              icon: const Icon(Icons.add),
              label: const Text('Transaction'),
            ),
            body: people.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Add a person, then note each time you give them money or take money from them. Jarvis keeps what is owed each way.',
                        textAlign: TextAlign.center,
                        style: tt.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      Row(children: [
                        tile('To receive', t.receive, 'from ${t.receiveFrom} ${t.receiveFrom == 1 ? 'person' : 'people'}', scheme.primary),
                        tile('To pay', t.pay, 'to ${t.payTo} ${t.payTo == 1 ? 'person' : 'people'}', scheme.error),
                      ]),
                      FilledButton.tonalIcon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LoanTxPage(store: s))),
                        icon: const Icon(Icons.swap_horiz),
                        label: Text('All transactions (${txs.length})'),
                      ),
                      const SizedBox(height: 8),
                      for (final p in people)
                        Builder(builder: (context) {
                          final b = Loans.balance(p['id'] as int, txs);
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(child: Text('${p['name']}'.characters.first.toUpperCase())),
                              title: Text('${p['name']}', style: tt.titleMedium),
                              trailing: Text(_owes(s, b),
                                  style: tt.titleSmall?.copyWith(color: b > 0 ? scheme.primary : (b < 0 ? scheme.error : scheme.onSurfaceVariant))),
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LoanPersonPage(store: s, personId: p['id'] as int))),
                            ),
                          );
                        }),
                    ],
                  ),
          );
        },
      );
}

/// One person: what is owed and every transaction with them, newest first.
class LoanPersonPage extends StatelessWidget {
  const LoanPersonPage({super.key, required this.store, required this.personId});
  final Store store;
  final int personId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final s = store;
          final p = s.byId('loanPeople', personId);
          if (p == null) return const Scaffold(body: Center(child: Text('This person was deleted.')));
          final scheme = Theme.of(context).colorScheme;
          final tt = Theme.of(context).textTheme;
          final mine = _txs(s).where((t) => t['person'] == personId).toList()..sort((a, b) => (b['ts'] as int).compareTo(a['ts'] as int));
          final b = Loans.balance(personId, mine);
          return Scaffold(
            appBar: AppBar(
              title: Text('${p['name']}'),
              actions: [
                IconButton(tooltip: 'Edit person', icon: const Icon(Icons.edit_outlined), onPressed: () => editLoanPerson(context, s, p)),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(b == 0 ? 'Settled' : s.money(b.abs()), style: tt.headlineMedium?.copyWith(color: b > 0 ? scheme.primary : (b < 0 ? scheme.error : null))),
                Text(b > 0 ? '${p['name']} owes you' : (b < 0 ? 'You owe ${p['name']}' : 'Nothing owed either way'),
                    style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => editLoanTx(context, s, personId: personId, type: 'gave'),
                      icon: const Icon(Icons.call_made),
                      label: const Text('I gave'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => editLoanTx(context, s, personId: personId, type: 'took'),
                      icon: const Icon(Icons.call_received),
                      label: const Text('I took'),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                if (mine.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No transactions yet.')),
                for (final t in mine) _txCard(context, s, t, showPerson: false),
              ],
            ),
          );
        },
      );
}

Widget _txCard(BuildContext context, Store s, Map<String, dynamic> t, {required bool showPerson}) {
  final scheme = Theme.of(context).colorScheme;
  final gave = t['type'] == 'gave';
  final who = s.byId('loanPeople', t['person'] as int)?['name'] ?? 'Deleted person';
  final why = (t['why'] as String?) ?? '';
  return Card(
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: (gave ? scheme.primary : scheme.error).withValues(alpha: 0.12),
        child: Icon(gave ? Icons.call_made : Icons.call_received, color: gave ? scheme.primary : scheme.error),
      ),
      title: Text(showPerson ? '${gave ? 'Gave' : 'Took'}: $who' : (gave ? 'I gave' : 'I took')),
      subtitle: Text([if (why.isNotEmpty) why, if (t['method'] != null) t['method'], _when(t['ts'] as int)].join('  ·  ')),
      trailing: Text('${gave ? '+' : '-'}${s.money(t['amount'] as num)}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: gave ? scheme.primary : scheme.error)),
      onTap: () => editLoanTx(context, s, tx: t),
    ),
  );
}

/// Every transaction, with search, a gave or took filter and a time range.
class LoanTxPage extends StatefulWidget {
  const LoanTxPage({super.key, required this.store});
  final Store store;
  @override
  State<LoanTxPage> createState() => _LoanTxPageState();
}

class _LoanTxPageState extends State<LoanTxPage> {
  String _type = 'all';
  String _range = 'all';
  String _q = '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final s = widget.store;
          final now = DateTime.now();
          final q = _q.trim().toLowerCase();
          bool matches(Map<String, dynamic> t) {
            if (_type != 'all' && t['type'] != _type) return false;
            if (!Loans.inRange(t['ts'] as int, _range, now)) return false;
            if (q.isEmpty) return true;
            final who = '${s.byId('loanPeople', t['person'] as int)?['name'] ?? ''}';
            return '$who ${t['why'] ?? ''} ${t['note'] ?? ''}'.toLowerCase().contains(q);
          }

          final shown = _txs(s).where(matches).toList()..sort((a, b) => (b['ts'] as int).compareTo(a['ts'] as int));
          return Scaffold(
            appBar: AppBar(title: const Text('Transactions')),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => editLoanTx(context, s),
              icon: const Icon(Icons.add),
              label: const Text('Transaction'),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                TextField(
                  onChanged: (v) => setState(() => _q = v),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name, reason or note'),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  for (final e in {'all': 'All', 'gave': 'I gave', 'took': 'I took'}.entries)
                    ChoiceChip(label: Text(e.value), selected: _type == e.key, onSelected: (_) => setState(() => _type = e.key)),
                ]),
                Wrap(spacing: 8, children: [
                  for (final r in Loans.ranges) ChoiceChip(label: Text(_rangeNames[r]!), selected: _range == r, onSelected: (_) => setState(() => _range = r)),
                ]),
                const SizedBox(height: 8),
                if (shown.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No transactions match.')),
                for (final t in shown) _txCard(context, s, t, showPerson: true),
              ],
            ),
          );
        },
      );
}

Future<void> editLoanPerson(BuildContext context, Store s, Rec? p) async {
  final name = TextEditingController(text: p?['name'] as String? ?? '');
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(p == null ? 'New person' : 'Edit person'),
        content: TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: 'Name', errorText: error)),
        actions: [
          if (p != null)
            TextButton(
              onPressed: () async {
                final mine = _txs(s).where((t) => t['person'] == p['id']).toList();
                final ok = await showDialog<bool>(
                  context: ctx,
                  builder: (c2) => AlertDialog(
                    title: Text('Delete ${p['name']}?'),
                    content: Text(mine.isEmpty ? 'You can undo it in Activity and undo.' : 'This also deletes their ${mine.length} transactions.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(c2, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok != true) return;
                Haptics.warn();
                for (final t in mine) {
                  s.removeRec('loans', t, 'Deleted a loan with ${p['name']}');
                }
                s.removeRec('loanPeople', p, 'Deleted ${p['name']} from loans');
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final n = name.text.trim();
              if (n.isEmpty) return setD(() => error = Haptics.rejected() ?? 'Enter a name');
              if (p == null) {
                final rec = {'id': s.nextId(), 'name': n};
                s.list('loanPeople').add(rec);
                s.logAction('Added $n to loans', [
                  {'op': 'rm', 'col': 'loanPeople', 'id': rec['id']},
                ]);
                s.save();
              } else {
                await s.updateRec('loanPeople', p, 'Renamed $n', (r) => r['name'] = n);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// Adds or edits one transaction. [personId] and [type] preset a new one.
Future<void> editLoanTx(BuildContext context, Store s, {Rec? tx, int? personId, String? type}) async {
  final people = s.list('loanPeople');
  var person = (tx?['person'] as int?) ?? personId ?? (people.isEmpty ? -1 : null);
  var kind = (tx?['type'] as String?) ?? type ?? 'gave';
  var method = tx?['method'] as String? ?? 'Cash';
  var at = tx == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(tx['ts'] as int);
  final amount = TextEditingController(text: tx == null ? '' : '${tx['amount']}');
  final why = TextEditingController(text: tx?['why'] as String? ?? '');
  final note = TextEditingController(text: tx?['note'] as String? ?? '');
  final newName = TextEditingController();
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(tx == null ? 'New transaction' : 'Edit transaction'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            DropdownButtonFormField<int>(
              initialValue: person,
              decoration: const InputDecoration(labelText: 'Person'),
              items: [
                for (final p in people) DropdownMenuItem(value: p['id'] as int, child: Text('${p['name']}')),
                const DropdownMenuItem(value: -1, child: Text('New person…')),
              ],
              onChanged: (v) => setD(() => person = v),
            ),
            if (person == -1) TextField(controller: newName, decoration: const InputDecoration(labelText: 'Their name')),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('I gave'), selected: kind == 'gave', onSelected: (_) => setD(() => kind = 'gave')),
              ChoiceChip(label: const Text('I took'), selected: kind == 'took', onSelected: (_) => setD(() => kind = 'took')),
            ]),
            Text(kind == 'gave' ? 'They took the money from me' : 'I took the money from them', style: Theme.of(context).textTheme.bodySmall),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Amount', errorText: error),
            ),
            TextField(controller: why, decoration: const InputDecoration(labelText: 'Reason (optional)')),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final m in Loans.methods) ChoiceChip(label: Text(m), selected: method == m, onSelected: (_) => setD(() => method = m)),
            ]),
            Row(children: [
              Expanded(
                child: TextButton.icon(
                  icon: const Icon(Icons.event_outlined),
                  label: Text(dayKey(at)),
                  onPressed: () async {
                    final d = await showDatePicker(context: ctx, initialDate: at, firstDate: DateTime(2000), lastDate: DateTime(2100));
                    if (d != null) setD(() => at = DateTime(d.year, d.month, d.day, at.hour, at.minute));
                  },
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  icon: const Icon(Icons.schedule),
                  label: Text(TimeOfDay.fromDateTime(at).format(ctx)),
                  onPressed: () async {
                    final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(at));
                    if (t != null) setD(() => at = DateTime(at.year, at.month, at.day, t.hour, t.minute));
                  },
                ),
              ),
            ]),
            TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Note (optional)')),
          ]),
        ),
        actions: [
          if (tx != null)
            TextButton(
              onPressed: () {
                Haptics.warn();
                s.removeRec('loans', tx, 'Deleted a loan transaction');
                Navigator.pop(ctx);
              },
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final v = num.tryParse(amount.text.trim().replaceAll(',', ''));
              if (person == null) return setD(() => error = Haptics.rejected() ?? 'Pick a person');
              if (v == null || v <= 0) return setD(() => error = Haptics.rejected() ?? 'Enter the amount');
              if (person == -1 && newName.text.trim().isEmpty) return setD(() => error = Haptics.rejected() ?? 'Enter their name');
              final undo = <Rec>[];
              var pid = person!;
              if (pid == -1) {
                final p = {'id': s.nextId(), 'name': newName.text.trim()};
                s.list('loanPeople').add(p);
                undo.add({'op': 'rm', 'col': 'loanPeople', 'id': p['id']});
                pid = p['id'] as int;
              }
              final name = s.byId('loanPeople', pid)?['name'];
              final fields = {
                'person': pid,
                'type': kind,
                'amount': v,
                'method': method,
                'ts': at.millisecondsSinceEpoch,
                if (why.text.trim().isNotEmpty) 'why': why.text.trim(),
                if (note.text.trim().isNotEmpty) 'note': note.text.trim(),
              };
              if (tx == null) {
                final rec = {'id': s.nextId(), ...fields};
                s.list('loans').add(rec);
                undo.add({'op': 'rm', 'col': 'loans', 'id': rec['id']});
                s.logAction('${kind == 'gave' ? 'Gave' : 'Took'} ${s.money(v)} ${kind == 'gave' ? 'to' : 'from'} $name', undo);
                s.save();
              } else {
                await s.updateRec('loans', tx, 'Edited a loan with $name', (r) {
                  r
                    ..remove('why')
                    ..remove('note')
                    ..addAll(fields);
                });
              }
              Haptics.tap();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
