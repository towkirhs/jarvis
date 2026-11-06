import 'package:flutter/material.dart';

import 'haptics.dart';
import 'rent.dart';
import 'store.dart';

String _date(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day} ${Rent.monthNames[d.month - 1].substring(0, 3)} ${d.year}';
}

/// All rooms: who lives there and what they owe.
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
        final dues = {for (final r in rooms) r['id']: Rent.totalDue(r, s.list('rentPays'), s.list('roomBills'), now)};
        final owed = dues.values.where((d) => d > 0).fold<num>(0, (a, b) => a + b);
        return Scaffold(
          appBar: AppBar(title: const Text('Rooms and rent')),
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
                      'Add your first room: its number, the tenant, monthly rent and advance.',
                      textAlign: TextAlign.center,
                      style: tt.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    Text(owed > 0 ? '${s.money(owed)} due' : 'Everyone is paid up', style: tt.headlineSmall),
                    const SizedBox(height: 2),
                    Text(
                      'Across ${rooms.length} ${rooms.length == 1 ? 'room' : 'rooms'}, up to ${Rent.name(Rent.key(now))}',
                      style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    for (final r in rooms)
                      Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          title: Text('Room ${r['number']}', style: tt.titleMedium),
                          subtitle: Text('${r['tenant']}\nRent ${s.money(r['rent'] as num)}, advance ${s.money(r['advance'] as num)}'),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                dues[r['id']]! > 0 ? s.money(dues[r['id']]!) : 'Paid up',
                                style: tt.titleMedium?.copyWith(color: dues[r['id']]! > 0 ? scheme.error : scheme.primary),
                              ),
                              if (dues[r['id']]! > 0) Text('due', style: tt.bodySmall),
                            ],
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => RoomPage(store: s, roomId: r['id'] as int)),
                          ),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

/// One room: its months, newest first, each with rent, bill, payments and what is due.
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
        final total = Rent.totalDue(r, pays, bills, now);
        final months = Rent.months(r['start'] as String, now).reversed.toList();
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
                total > 0 ? '${s.money(total)} due' : (total < 0 ? '${s.money(-total)} paid ahead' : 'Paid up'),
                style: tt.titleLarge?.copyWith(color: total > 0 ? scheme.error : scheme.primary),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _payment(context, s, r),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Record payment'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _bill(context, s, r),
                      icon: const Icon(Icons.bolt_outlined),
                      label: const Text('Add bill'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final m in months) _month(context, s, r, m, pays, bills),
            ],
          ),
        );
      },
    );
  }

  Widget _month(BuildContext context, Store s, Rec r, String m, List<Rec> pays, List<Rec> bills) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final x = Rent.month(r, m, pays, bills);
    final mine = pays.where((p) => p['room'] == r['id'] && p['month'] == m).toList()
      ..sort((a, b) => (a['paidAt'] as int).compareTo(b['paidAt'] as int));
    final bill = bills.where((b) => b['room'] == r['id'] && b['month'] == m).toList();
    Widget line(String left, String right, {Color? color, VoidCallback? onLongPress}) => InkWell(
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(child: Text(left, style: TextStyle(color: color))),
              Text(right, style: TextStyle(color: color)),
            ]),
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(Rent.name(m), style: tt.titleSmall)),
              Text(
                x.due > 0 ? '${s.money(x.due)} due' : (x.due < 0 ? '${s.money(-x.due)} extra' : 'Paid'),
                style: tt.titleSmall?.copyWith(color: x.due > 0 ? scheme.error : scheme.primary),
              ),
            ]),
            const SizedBox(height: 6),
            line('Rent', s.money(x.rent)),
            for (final b in bill)
              line('Electricity bill', s.money(b['amount'] as num), onLongPress: () => _delete(context, s, 'roomBills', b, 'Deleted a bill for room ${r['number']}')),
            for (final p in mine)
              line('Paid on ${_date(p['paidAt'] as int)}', '- ${s.money(p['amount'] as num)}',
                  color: scheme.primary,
                  onLongPress: () => _delete(context, s, 'rentPays', p, 'Deleted a payment for room ${r['number']}')),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, Store s, String col, Rec rec, String desc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(col == 'rentPays' ? 'Delete this payment?' : 'Delete this bill?'),
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

  /// Months you can pay or bill for: from move-in to next month.
  List<String> _choices(Rec r) {
    final now = DateTime.now();
    return Rent.months(r['start'] as String, DateTime(now.year, now.month + 1)).reversed.toList();
  }

  Future<void> _payment(BuildContext context, Store s, Rec r) async {
    // Default to the oldest month still owing, else this month.
    final now = DateTime.now();
    final owing = Rent.months(r['start'] as String, now)
        .where((m) => Rent.month(r, m, s.list('rentPays'), s.list('roomBills')).due > 0)
        .toList();
    var month = owing.isEmpty ? Rent.key(now) : owing.first;
    var paidAt = DateTime(now.year, now.month, now.day);
    final due = Rent.month(r, month, s.list('rentPays'), s.list('roomBills')).due;
    final amount = TextEditingController(text: due > 0 ? '$due' : '${r['rent']}');
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Payment for room ${r['number']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: month,
                decoration: const InputDecoration(labelText: 'For the month of'),
                items: [for (final m in _choices(r)) DropdownMenuItem(value: m, child: Text(Rent.name(m)))],
                onChanged: (v) => setD(() {
                  month = v!;
                  final d = Rent.month(r, month, s.list('rentPays'), s.list('roomBills')).due;
                  amount.text = d > 0 ? '$d' : '${r['rent']}';
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Amount paid', errorText: error),
              ),
              const SizedBox(height: 12),
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
                final v = num.tryParse(amount.text.trim().replaceAll(',', ''));
                if (v == null || v <= 0) return setD(() => error = 'Enter the amount paid');
                final rec = {
                  'id': s.nextId(),
                  'room': r['id'],
                  'month': month,
                  'amount': v,
                  'paidAt': paidAt.millisecondsSinceEpoch,
                };
                s.list('rentPays').add(rec);
                s.logAction('Room ${r['number']}: ${s.money(v)} for ${Rent.name(month)}', [
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

  Future<void> _bill(BuildContext context, Store s, Rec r) async {
    var month = Rent.key(DateTime.now());
    final amount = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Electricity bill, room ${r['number']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: month,
                decoration: const InputDecoration(labelText: 'Month'),
                items: [for (final m in _choices(r)) DropdownMenuItem(value: m, child: Text(Rent.name(m)))],
                onChanged: (v) => setD(() => month = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Bill amount', errorText: error),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final v = num.tryParse(amount.text.trim().replaceAll(',', ''));
                if (v == null || v <= 0) return setD(() => error = 'Enter the bill amount');
                final rec = {'id': s.nextId(), 'room': r['id'], 'month': month, 'amount': v};
                s.list('roomBills').add(rec);
                s.logAction('Room ${r['number']}: bill ${s.money(v)} for ${Rent.name(month)}', [
                  {'op': 'rm', 'col': 'roomBills', 'id': rec['id']},
                ]);
                s.save();
                Haptics.tap();
                Navigator.pop(ctx);
              },
              child: const Text('Save bill'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Add a room, or change one (with Delete).
Future<void> editRoom(BuildContext context, Store s, Rec? r) async {
  final number = TextEditingController(text: r?['number'] as String?);
  final tenant = TextEditingController(text: r?['tenant'] as String?);
  final rent = TextEditingController(text: r == null ? '' : '${r['rent']}');
  final advance = TextEditingController(text: r == null ? '' : '${r['advance']}');
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
              TextField(
                controller: number,
                autofocus: r == null,
                decoration: const InputDecoration(labelText: 'Room number'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tenant,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Tenant name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: rent,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Monthly rent'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: advance,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Advance paid'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: start,
                decoration: const InputDecoration(labelText: 'Rent counts from'),
                items: [for (final m in startChoices) DropdownMenuItem(value: m, child: Text(Rent.name(m)))],
                onChanged: (v) => setD(() => start = v!),
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
              final rentV = num.tryParse(rent.text.trim().replaceAll(',', ''));
              final advV = advance.text.trim().isEmpty ? 0 : num.tryParse(advance.text.trim().replaceAll(',', ''));
              if (n.isEmpty || tenant.text.trim().isEmpty) return setD(() => error = 'Add the room number and tenant name.');
              if (rentV == null || rentV <= 0) return setD(() => error = 'Add the monthly rent.');
              if (advV == null || advV < 0) return setD(() => error = 'The advance must be a number.');
              final rec = r ?? {'id': s.nextId()};
              final old = r == null ? null : copyRec(r);
              rec
                ..['number'] = n
                ..['tenant'] = tenant.text.trim()
                ..['rent'] = rentV
                ..['advance'] = advV
                ..['start'] = start;
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
