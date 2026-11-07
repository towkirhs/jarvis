import 'package:flutter/material.dart';

import 'haptics.dart';
import 'rent.dart';
import 'store.dart';

String _date(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day} ${Rent.monthNames[d.month - 1].substring(0, 3)} ${d.year}';
}

num? _amount(TextEditingController c) => num.tryParse(c.text.trim().replaceAll(',', ''));

/// What happened this month across the house: rent collected, house expenses, and what is left.
({num collected, num spent}) _thisMonth(Store s, DateTime now) {
  final m = Rent.key(now);
  bool inMonth(int ms) => Rent.key(DateTime.fromMillisecondsSinceEpoch(ms)) == m;
  return (
    collected: s.list('rentPays').where((p) => inMonth(p['paidAt'] as int)).fold<num>(0, (a, p) => a + (p['amount'] as num)),
    spent: s.list('houseCosts').where((c) => inMonth(c['ts'] as int)).fold<num>(0, (a, c) => a + (c['amount'] as num)),
  );
}

/// All rooms: who lives there, what they owe, and the house's month.
class RentPage extends StatelessWidget {
  const RentPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final s = store;
        final scheme = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;
        final now = DateTime.now();
        final rooms = s.list('rooms').toList()..sort((a, b) => '${a['number']}'.compareTo('${b['number']}'));
        final pays = s.list('rentPays');
        final bills = s.list('roomBills');
        final dues = {for (final r in rooms) r['id']: Rent.due(r, pays, bills, now)};
        final owed = dues.values.where((d) => d > 0).fold<num>(0, (a, b) => a + b);
        final month = _thisMonth(s, now);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Rooms and rent'),
            actions: [
              if (rooms.isNotEmpty)
                IconButton(
                  tooltip: "Enter a month's bills",
                  icon: const Icon(Icons.receipt_long_outlined),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BillsPage(store: s))),
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => editRoom(context, s, null),
            icon: const Icon(Icons.add),
            label: const Text('Room'),
          ),
          body: rooms.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Add your first room: its number, the tenant, monthly rent, advance, and anything they already owed.',
                      textAlign: TextAlign.center,
                      style: tt.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    Text(owed > 0 ? '${s.money(owed)} due' : 'Everyone is paid up', style: tt.headlineSmall),
                    Text(
                      'From ${rooms.length} ${rooms.length == 1 ? 'room' : 'rooms'}, rent and bills up to ${Rent.name(Rent.key(now))}',
                      style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: InkWell(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HouseCostsPage(store: s))),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(Rent.name(Rent.key(now)), style: tt.titleSmall)),
                              Text('House expenses', style: tt.labelLarge?.copyWith(color: scheme.primary)),
                              Icon(Icons.chevron_right, color: scheme.primary),
                            ]),
                            const SizedBox(height: 12),
                            Row(children: [
                              _figure(context, s.money(month.collected), 'collected'),
                              _figure(context, s.money(month.spent), 'spent on the house'),
                              _figure(context, s.money(month.collected - month.spent), 'left'),
                            ]),
                          ]),
                        ),
                      ),
                    ),
                    for (final r in rooms)
                      Builder(builder: (context) {
                        final due = dues[r['id']]!;
                        final since = Rent.unpaidSince(r, pays, bills, now);
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            title: Text('Room ${r['number']}', style: tt.titleMedium),
                            subtitle: Text('${r['tenant']}\nRent ${s.money(r['rent'] as num)}'),
                            isThreeLine: true,
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  due > 0 ? s.money(due) : (due < 0 ? '${s.money(-due)} ahead' : 'Paid up'),
                                  style: tt.titleMedium?.copyWith(color: due > 0 ? scheme.error : scheme.primary),
                                ),
                                if (since != null) Text('unpaid since ${Rent.name(since, short: true)}', style: tt.bodySmall),
                              ],
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => RoomPage(store: s, roomId: r['id'] as int)),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
        );
      },
    );
  }

  Widget _figure(BuildContext context, String value, String label) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

/// One room's statement: a month at a time, newest first.
class RoomPage extends StatelessWidget {
  const RoomPage({super.key, required this.store, required this.roomId});
  final Store store;
  final int roomId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final s = store;
        final r = s.byId('rooms', roomId);
        if (r == null) return const Scaffold(body: Center(child: Text('This room was deleted.')));
        final scheme = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;
        final now = DateTime.now();
        final pays = s.list('rentPays');
        final bills = s.list('roomBills');
        final due = Rent.due(r, pays, bills, now);
        final since = Rent.unpaidSince(r, pays, bills, now);
        final months = Rent.months(r['start'] as String, now).reversed.toList();
        final upcoming = Rent.billsOf(roomId, Rent.key(now), bills);
        final costs = s.list('houseCosts').where((c) => c['room'] == roomId).toList();
        return Scaffold(
          appBar: AppBar(
            title: Text('Room ${r['number']}'),
            actions: [
              IconButton(tooltip: 'Edit room', icon: const Icon(Icons.edit_outlined), onPressed: () => editRoom(context, s, r)),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text('${r['tenant']}', style: tt.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Rent ${s.money(r['rent'] as num)} a month since ${Rent.name(r['start'] as String)}. '
                'Advance ${s.money(r['advance'] as num)}.',
                style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Text(
                due > 0 ? '${s.money(due)} due' : (due < 0 ? '${s.money(-due)} paid ahead' : 'Paid up'),
                style: tt.titleLarge?.copyWith(color: due > 0 ? scheme.error : scheme.primary),
              ),
              if (since != null)
                Text('Part of it unpaid since ${Rent.name(since)}', style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _payment(context, s, r, due),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Record payment'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _bills(context, s, r),
                      icon: const Icon(Icons.bolt_outlined),
                      label: const Text('Add bills'),
                    ),
                  ),
                ],
              ),
              if (upcoming.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Comes with ${Rent.name(Rent.shift(Rent.key(now), 1))} rent', style: tt.titleSmall),
                      const SizedBox(height: 8),
                      for (final b in upcoming)
                        _line(context, '${Rent.billKinds[b['kind']] ?? 'Bill'} (${Rent.name(Rent.key(now), short: true)})',
                            s.money(b['amount'] as num),
                            onLongPress: () => _delete(context, s, 'roomBills', b, 'Deleted a bill for room ${r['number']}')),
                    ]),
                  ),
                ),
              const SizedBox(height: 4),
              for (final m in months) _month(context, s, r, Rent.month(r, m, pays, bills)),
              if (costs.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Spent on this room', style: tt.titleSmall),
                for (final c in costs.reversed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(c['what'] as String),
                    subtitle: Text(_date(c['ts'] as int)),
                    trailing: Text(s.money(c['amount'] as num)),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  static Widget _line(BuildContext context, String left, String right,
          {Color? color, bool bold = false, VoidCallback? onLongPress}) =>
      InkWell(
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(left, style: TextStyle(color: color, fontWeight: bold ? FontWeight.w700 : null))),
            Text(right, style: TextStyle(color: color, fontWeight: bold ? FontWeight.w700 : null)),
          ]),
        ),
      );

  Widget _month(BuildContext context, Store s, Rec r, MonthLine x) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final billMonth = Rent.name(Rent.shift(x.month, -1), short: true);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Rent.name(x.month), style: tt.titleSmall),
            const SizedBox(height: 8),
            if (x.carried != 0)
              _line(context, x.carried > 0 ? 'Owed from before' : 'Paid ahead before', s.money(x.carried.abs()),
                  color: x.carried > 0 ? scheme.error : scheme.primary),
            _line(context, 'Rent', s.money(x.rent)),
            for (final b in x.bills)
              _line(context, '${Rent.billKinds[b['kind']] ?? 'Bill'} ($billMonth)', s.money(b['amount'] as num),
                  onLongPress: () => _delete(context, s, 'roomBills', b, 'Deleted a bill for room ${r['number']}')),
            const Divider(height: 12),
            _line(context, 'To pay', s.money(x.toPay), bold: true),
            for (final p in x.payments)
              _line(context, 'Paid ${_date(p['paidAt'] as int)}', '- ${s.money(p['amount'] as num)}',
                  color: scheme.primary,
                  onLongPress: () => _delete(context, s, 'rentPays', p, 'Deleted a payment for room ${r['number']}')),
            _line(
              context,
              x.left > 0 ? 'Left, carried on' : (x.left < 0 ? 'Paid ahead' : 'Settled'),
              s.money(x.left.abs()),
              bold: true,
              color: x.left > 0 ? scheme.error : scheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _delete(BuildContext context, Store s, String col, Rec rec, String desc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(col == 'rentPays' ? 'Delete this payment?' : (col == 'roomBills' ? 'Delete this bill?' : 'Delete this expense?')),
        content: const Text('You can undo it in Activity and undo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    Haptics.warn();
    s.removeRec(col, rec, desc);
  }

  Future<void> _payment(BuildContext context, Store s, Rec r, num due) async {
    final now = DateTime.now();
    var paidAt = DateTime(now.year, now.month, now.day);
    final amount = TextEditingController(text: '${due > 0 ? due : r['rent']}');
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Payment, room ${r['number']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (due > 0) Align(alignment: Alignment.centerLeft, child: Text('Owed now: ${s.money(due)}')),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Amount paid', errorText: error),
              ),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text('Paid on ${_date(paidAt.millisecondsSinceEpoch)}'),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: paidAt,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(now.year + 1),
                  );
                  if (d != null) setD(() => paidAt = d);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final v = _amount(amount);
                if (v == null || v <= 0) return setD(() => error = Haptics.rejected() ?? 'Enter the amount paid');
                final rec = {
                  'id': s.nextId(),
                  'room': r['id'],
                  'amount': v,
                  'paidAt': paidAt.millisecondsSinceEpoch,
                };
                s.list('rentPays').add(rec);
                s.logAction('Room ${r['number']}: paid ${s.money(v)}', [
                  {'op': 'rm', 'col': 'rentPays', 'id': rec['id']},
                ]);
                s.save();
                Haptics.tap();
                Navigator.pop(ctx);
              },
              child: const Text('Save payment'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _bills(BuildContext context, Store s, Rec r) async {
    final now = DateTime.now();
    var month = Rent.key(DateTime(now.year, now.month - 1));
    final choices = Rent.months(Rent.shift(r['start'] as String, -1), now).reversed.toList();
    if (!choices.contains(month)) month = choices.first;
    final fields = {for (final k in Rent.billKinds.keys) k: TextEditingController()};
    void fill() {
      for (final e in fields.entries) {
        final b = Rent.billsOf(r['id'] as int, month, s.list('roomBills')).where((b) => (b['kind'] ?? 'electricity') == e.key);
        e.value.text = b.isEmpty ? '' : '${b.first['amount']}';
      }
    }

    fill();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Bills, room ${r['number']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: month,
                  decoration: const InputDecoration(labelText: 'Used in'),
                  items: [for (final m in choices) DropdownMenuItem(value: m, child: Text(Rent.name(m)))],
                  onChanged: (v) => setD(() {
                    month = v!;
                    fill();
                  }),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('Paid with ${Rent.name(Rent.shift(month, 1))} rent.', style: Theme.of(ctx).textTheme.bodySmall),
                ),
                for (final e in fields.entries) ...[
                  TextField(
                    controller: e.value,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: Rent.billKinds[e.key]),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                saveBills(s, r, month, {for (final e in fields.entries) e.key: _amount(e.value)});
                Navigator.pop(ctx);
              },
              child: const Text('Save bills'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Replaces a room's bills for a month with [amounts] (empty or 0 removes that kind). Undoable.
void saveBills(Store s, Rec r, String month, Map<String, num?> amounts) {
  final old = Rent.billsOf(r['id'] as int, month, s.list('roomBills'));
  final undo = <Map<String, dynamic>>[];
  for (final b in old) {
    s.list('roomBills').remove(b);
    undo.add({'op': 'put', 'col': 'roomBills', 'rec': copyRec(b)});
  }
  for (final e in amounts.entries) {
    final v = e.value;
    if (v == null || v <= 0) continue;
    final rec = {'id': s.nextId(), 'room': r['id'], 'month': month, 'kind': e.key, 'amount': v};
    s.list('roomBills').add(rec);
    undo.add({'op': 'rm', 'col': 'roomBills', 'id': rec['id']});
  }
  if (undo.isEmpty) return;
  s.logAction('Room ${r['number']}: bills for ${Rent.name(month)}', undo);
  s.save();
  Haptics.tap();
}

/// A month's bills for every room on one screen, the way you get them.
class BillsPage extends StatefulWidget {
  const BillsPage({super.key, required this.store});
  final Store store;

  @override
  State<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends State<BillsPage> {
  late String _month = Rent.key(DateTime(DateTime.now().year, DateTime.now().month - 1));
  final _fields = <int, Map<String, TextEditingController>>{};

  Store get s => widget.store;

  List<Rec> get _rooms => s.list('rooms').toList()..sort((a, b) => '${a['number']}'.compareTo('${b['number']}'));

  void _fill() {
    for (final r in _rooms) {
      final f = _fields.putIfAbsent(r['id'] as int, () => {for (final k in Rent.billKinds.keys) k: TextEditingController()});
      for (final e in f.entries) {
        final b = Rent.billsOf(r['id'] as int, _month, s.list('roomBills')).where((b) => (b['kind'] ?? 'electricity') == e.key);
        e.value.text = b.isEmpty ? '' : '${b.first['amount']}';
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _fill();
  }

  @override
  void dispose() {
    for (final f in _fields.values) {
      for (final c in f.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final choices = Rent.months(Rent.key(DateTime(now.year - 1, now.month)), now).reversed.toList();
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Bills')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _month,
            decoration: const InputDecoration(labelText: 'Used in'),
            items: [for (final m in choices) DropdownMenuItem(value: m, child: Text(Rent.name(m)))],
            onChanged: (v) => setState(() {
              _month = v!;
              _fill();
            }),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('These are paid with ${Rent.name(Rent.shift(_month, 1))} rent.', style: tt.bodySmall),
          ),
          for (final r in _rooms)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Room ${r['number']}, ${r['tenant']}', style: tt.titleSmall),
                  const SizedBox(height: 8),
                  Row(children: [
                    for (final k in Rent.billKinds.keys) ...[
                      Expanded(
                        child: TextField(
                          controller: _fields[r['id']]![k],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: Rent.billKinds[k] == 'Other bill' ? 'Other' : Rent.billKinds[k],
                            isDense: true,
                          ),
                        ),
                      ),
                      if (k != Rent.billKinds.keys.last) const SizedBox(width: 8),
                    ],
                  ]),
                ]),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              for (final r in _rooms) {
                saveBills(s, r, _month, {
                  for (final e in _fields[r['id']]!.entries) e.key: _amount(e.value),
                });
              }
              Navigator.pop(context);
            },
            child: const Text('Save bills'),
          ),
        ],
      ),
    );
  }
}

/// Money spent on the house: repairs, fixing things, anything. Optionally for one room.
class HouseCostsPage extends StatelessWidget {
  const HouseCostsPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final s = store;
        final tt = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        final now = DateTime.now();
        final costs = s.list('houseCosts').toList()..sort((a, b) => (b['ts'] as int).compareTo(a['ts'] as int));
        final byMonth = <String, List<Rec>>{};
        for (final c in costs) {
          byMonth.putIfAbsent(Rent.key(DateTime.fromMillisecondsSinceEpoch(c['ts'] as int)), () => []).add(c);
        }
        final year = '${now.year}';
        num sum(Iterable<Rec> l) => l.fold<num>(0, (a, c) => a + (c['amount'] as num));
        final yearCosts = sum(costs.where((c) => Rent.key(DateTime.fromMillisecondsSinceEpoch(c['ts'] as int)).startsWith(year)));
        final yearRent = sum(s.list('rentPays').where((p) => DateTime.fromMillisecondsSinceEpoch(p['paidAt'] as int).year == now.year));
        return Scaffold(
          appBar: AppBar(title: const Text('House expenses')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => addHouseCost(context, s),
            icon: const Icon(Icons.add),
            label: const Text('Expense'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Text('${s.money(yearRent - yearCosts)} left in $year', style: tt.headlineSmall),
              Text('${s.money(yearRent)} rent and bills collected, ${s.money(yearCosts)} spent on the house',
                  style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              if (costs.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text('Nothing spent yet. Add repairs, fixes and anything else the house costs you.',
                      style: tt.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              for (final m in byMonth.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Row(children: [
                    Expanded(child: Text(Rent.name(m.key), style: tt.titleSmall)),
                    Text(s.money(sum(m.value)), style: tt.titleSmall),
                  ]),
                ),
                Card(
                  child: Column(children: [
                    for (final c in m.value)
                      ListTile(
                        title: Text(c['what'] as String),
                        subtitle: Text([
                          _date(c['ts'] as int),
                          if (c['room'] != null && s.byId('rooms', c['room'] as int) != null)
                            'room ${s.byId('rooms', c['room'] as int)!['number']}',
                        ].join(', ')),
                        trailing: Text(s.money(c['amount'] as num)),
                        onLongPress: () => RoomPage._delete(context, s, 'houseCosts', c, 'Deleted expense ${c['what']}'),
                      ),
                  ]),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

Future<void> addHouseCost(BuildContext context, Store s) async {
  final what = TextEditingController();
  final amount = TextEditingController();
  final now = DateTime.now();
  var day = DateTime(now.year, now.month, now.day);
  int? room;
  String? error;
  final rooms = s.list('rooms').toList()..sort((a, b) => '${a['number']}'.compareTo('${b['number']}'));
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('House expense'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: what,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'What for, like Fixed the water pump'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Amount', errorText: error),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: room,
              decoration: const InputDecoration(labelText: 'For'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('The whole house')),
                for (final r in rooms) DropdownMenuItem<int?>(value: r['id'] as int, child: Text('Room ${r['number']}')),
              ],
              onChanged: (v) => setD(() => room = v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(_date(day.millisecondsSinceEpoch)),
              onTap: () async {
                final d = await showDatePicker(context: ctx, initialDate: day, firstDate: DateTime(2000), lastDate: DateTime(now.year + 1));
                if (d != null) setD(() => day = d);
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = _amount(amount);
              if (what.text.trim().isEmpty) return setD(() => error = Haptics.rejected() ?? 'Say what it was for');
              if (v == null || v <= 0) return setD(() => error = Haptics.rejected() ?? 'Enter the amount');
              final rec = {'id': s.nextId(), 'ts': day.millisecondsSinceEpoch, 'amount': v, 'what': what.text.trim(), 'room': room};
              s.list('houseCosts').add(rec);
              s.logAction('House expense: ${what.text.trim()} ${s.money(v)}', [
                {'op': 'rm', 'col': 'houseCosts', 'id': rec['id']},
              ]);
              s.save();
              Haptics.tap();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// Add a room, or change one (with Delete).
Future<void> editRoom(BuildContext context, Store s, Rec? r) async {
  final number = TextEditingController(text: r?['number'] as String?);
  final tenant = TextEditingController(text: r?['tenant'] as String?);
  final rent = TextEditingController(text: r == null ? '' : '${r['rent']}');
  final advance = TextEditingController(text: r == null ? '' : '${r['advance']}');
  final opening = TextEditingController(text: (r?['opening'] as num?) == null || r!['opening'] == 0 ? '' : '${r['opening']}');
  final now = DateTime.now();
  var start = (r?['start'] as String?) ?? Rent.key(now);
  final startChoices = Rent.months(Rent.key(DateTime(now.year - 3, now.month)), now).reversed.toList();
  if (!startChoices.contains(start)) startChoices.add(start);
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(r == null ? 'New room' : 'Room ${r['number']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: number, autofocus: r == null, decoration: const InputDecoration(labelText: 'Room number')),
              const SizedBox(height: 12),
              TextField(
                controller: tenant,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Tenant name'),
              ),
              const SizedBox(height: 12),
              TextField(controller: rent, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monthly rent')),
              const SizedBox(height: 12),
              TextField(controller: advance, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Advance paid')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: start,
                decoration: const InputDecoration(labelText: 'Rent counts from'),
                items: [for (final m in startChoices) DropdownMenuItem(value: m, child: Text(Rent.name(m)))],
                onChanged: (v) => setD(() => start = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: opening,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Already owed before that (optional)',
                  helperText: 'Old dues from past months, so nothing is lost',
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ),
            ],
          ),
        ),
        actions: [
          if (r != null)
            TextButton(
              onPressed: () {
                Haptics.warn();
                s.removeRec('rooms', r, 'Deleted room ${r['number']}');
                Navigator.pop(ctx);
              },
              child: const Text('Delete room'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final n = number.text.trim();
              final rentV = _amount(rent);
              final advV = advance.text.trim().isEmpty ? 0 : _amount(advance);
              final openV = opening.text.trim().isEmpty ? 0 : _amount(opening);
              if (n.isEmpty || tenant.text.trim().isEmpty) return setD(() => error = Haptics.rejected() ?? 'Add the room number and tenant name.');
              if (rentV == null || rentV <= 0) return setD(() => error = Haptics.rejected() ?? 'Add the monthly rent.');
              if (advV == null || advV < 0) return setD(() => error = Haptics.rejected() ?? 'The advance must be a number.');
              if (openV == null) return setD(() => error = Haptics.rejected() ?? 'What they already owed must be a number.');
              final rec = r ?? {'id': s.nextId()};
              final old = r == null ? null : copyRec(r);
              rec
                ..['number'] = n
                ..['tenant'] = tenant.text.trim()
                ..['rent'] = rentV
                ..['advance'] = advV
                ..['start'] = start
                ..['opening'] = openV;
              if (r == null) s.list('rooms').add(rec);
              s.logAction(r == null ? 'Added room $n' : 'Changed room $n', [
                r == null ? {'op': 'rm', 'col': 'rooms', 'id': rec['id']} : {'op': 'put', 'col': 'rooms', 'rec': old},
              ]);
              s.save();
              Haptics.tap();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
