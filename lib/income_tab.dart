import 'package:flutter/material.dart';

import 'haptics.dart';
import 'income.dart';
import 'loans.dart';
import 'loans_page.dart';
import 'rent.dart';
import 'rent_page.dart';
import 'store.dart';

/// Money's Income tab: everything that comes in or is owed, in one place. Rooms you rent out, salaries and
/// tuition, and loans, with what you can expect each month, what people owe you, and what you owe.
class IncomeTab extends StatelessWidget {
  const IncomeTab({super.key, required this.store});
  final Store store;

  static const _linkRules = ['rent', 'loanGave', 'loanTook'];

  @override
  Widget build(BuildContext context) {
    final s = store;
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final rooms = s.list('rooms');
    final pays = s.list('rentPays');
    final bills = s.list('roomBills');
    final upTo = rentUpTo(s, now);
    final rentDue = rooms.fold<num>(0, (a, r) {
      final d = Rent.dueThrough(r, pays, bills, now, upTo);
      return a + (d > 0 ? d : 0);
    });
    final rentMonthly = rooms.fold<num>(0, (a, r) => a + (r['rent'] as num));
    final sources = s.list('incomes');
    final got = s.list('incomePays');
    final salaryDue = sources.fold<num>(0, (a, x) {
      final d = Income.due(x, got, now);
      return a + (d > 0 ? d : 0);
    });
    final loans = Loans.totals([for (final p in s.list('loanPeople')) p['id'] as int], s.list('loans'));
    final linked = s.list('rules').where((r) => _linkRules.contains(r['builtin'])).toList();
    final linkOn = linked.isNotEmpty && linked.every((r) => r['on'] == true);

    Widget figure(String label, String value, {Color? color}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: tt.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: tt.titleMedium?.copyWith(color: color))),
          ]),
        );
    Widget section(String title, String line, IconData icon, Widget page) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            leading: Icon(icon, color: scheme.primary),
            title: Text(title, style: tt.titleMedium),
            subtitle: Text(line),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('What comes in', style: tt.titleMedium),
              const SizedBox(height: 12),
              Row(children: [
                figure('Each month', s.money(rentMonthly + Income.monthly(sources, now))),
                figure('People owe you', s.money(rentDue + salaryDue + loans.receive), color: scheme.primary),
                figure('You owe', s.money(loans.pay), color: loans.pay > 0 ? scheme.error : null),
              ]),
              const SizedBox(height: 8),
              Text(
                'Owed to you: rent ${s.money(rentDue)}, salaries ${s.money(salaryDue)}, loans ${s.money(loans.receive)}.',
                style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ]),
          ),
        ),
        section(
          'Rooms and rent',
          rooms.isEmpty
              ? 'Add the rooms you rent out'
              : '${rooms.length} room${rooms.length == 1 ? '' : 's'}, ${s.money(rentMonthly)} a month\n'
                  '${rentDue > 0 ? '${s.money(rentDue)} due up to ${Rent.name(upTo)}' : 'Everyone is paid up to ${Rent.name(upTo)}'}',
          Icons.meeting_room_outlined,
          RentPage(store: s),
        ),
        section(
          'Loans and debts',
          loans.receive == 0 && loans.pay == 0
              ? 'Money you lend or borrow'
              : 'To get ${s.money(loans.receive)} from ${loans.receiveFrom}, to pay ${s.money(loans.pay)} to ${loans.payTo}',
          Icons.swap_horiz,
          LoansPage(store: s),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text('Salary, tuition and other income', style: tt.titleMedium),
        ),
        if (sources.isEmpty)
          Text('Add a job, a tuition or anything that pays you by the month. Jarvis adds up what is due and what you received.',
              style: TextStyle(color: scheme.onSurfaceVariant)),
        for (final x in sources)
          Builder(builder: (context) {
            final due = Income.due(x, got, now);
            final active = Income.active(x, now);
            final months = (x['amount'] as num) <= 0 ? 0 : (due / (x['amount'] as num)).ceil();
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => editIncome(context, s, x),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${x['name']}', style: tt.titleMedium),
                        Text('${Income.kinds[x['kind']] ?? 'Other'}, ${s.money(x['amount'] as num)} a month${active ? '' : ', ended'}', style: tt.bodyMedium),
                        const SizedBox(height: 2),
                        Text(
                          due > 0
                              ? '${s.money(due)} not received yet ($months month${months == 1 ? '' : 's'})'
                              : (due < 0 ? '${s.money(-due)} received ahead' : 'Received up to last month'),
                          style: tt.bodySmall?.copyWith(color: due > 0 ? scheme.tertiary : scheme.onSurfaceVariant),
                        ),
                      ]),
                    ),
                  ),
                  FilledButton.tonal(onPressed: () => receiveIncome(context, s, x), child: const Text('Received')),
                ]),
              ),
            );
          }),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Put rent and loans into Money by themselves'),
          subtitle: const Text('Rent you record becomes income; money you lend leaves your account, money you take comes in. '
              'Salaries always go into Money when you tap Received.'),
          value: linkOn,
          onChanged: (on) {
            Haptics.toggle(on);
            for (final r in linked) {
              r['on'] = on;
            }
            s.logAction('${on ? 'Linked' : 'Unlinked'} rent and loans with Money', []);
            s.save();
          },
        ),
      ],
    );
  }
}

/// Records money received from an income source, and adds it to Money as income.
Future<void> receiveIncome(BuildContext context, Store s, Rec src) async {
  final amount = TextEditingController(text: '${src['amount']}');
  final accounts = [for (final a in s.list('accounts')) '${a['name']}'];
  var account = accounts.contains(src['account']) ? src['account'] as String : (accounts.isEmpty ? 'Cash' : accounts.first);
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text('Received from ${src['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Amount', prefixText: '${s.currency} '),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: account,
            decoration: const InputDecoration(labelText: 'Into'),
            items: [for (final a in accounts.isEmpty ? ['Cash'] : accounts) DropdownMenuItem(value: a, child: Text(a))],
            onChanged: (v) => setD(() => account = v ?? account),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = num.tryParse(amount.text.trim().replaceAll(',', ''));
              if (v == null || v <= 0) {
                Haptics.reject();
                return;
              }
              final undo = <Rec>[];
              final pay = {'id': s.nextId(), 'source': src['id'], 'amount': v, 'ts': DateTime.now().millisecondsSinceEpoch};
              s.list('incomePays').add(pay);
              undo.add({'op': 'rm', 'col': 'incomePays', 'id': pay['id']});
              s.addTx(type: 'income', amount: v, category: src['kind'] == 'tuition' ? 'Tuition' : 'Salary',
                  account: account, note: '${src['name']}', undo: undo);
              src['account'] = account;
              s.logAction('Received ${s.money(v)} from ${src['name']}', undo);
              s.save();
              Haptics.success();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// Adds an income source, or changes one (with Delete).
Future<void> editIncome(BuildContext context, Store s, Rec? src) async {
  final name = TextEditingController(text: '${src?['name'] ?? ''}');
  final amount = TextEditingController(text: src == null ? '' : '${src['amount']}');
  var kind = (src?['kind'] as String?) ?? 'tuition';
  final now = DateTime.now();
  var start = (src?['start'] as String?) ?? Rent.key(now);
  var ended = src?['end'] != null;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(src == null ? 'New income' : 'Edit income'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: name,
              autofocus: src == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'From, like Rafi tuition'),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in Income.kinds.entries)
                ChoiceChip(label: Text(e.value), showCheckmark: false, selected: kind == e.key, onSelected: (_) => setD(() => kind = e.key)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Pays a month', prefixText: '${s.currency} '),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: start,
              decoration: const InputDecoration(labelText: 'Since'),
              items: [
                for (final m in {start, ...[for (var k = 0; k < 24; k++) Rent.shift(Rent.key(now), -k)]}.toList()..sort((a, b) => b.compareTo(a)))
                  DropdownMenuItem(value: m, child: Text(Rent.name(m))),
              ],
              onChanged: (v) => setD(() => start = v ?? start),
            ),
            if (src != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('It has ended'),
                value: ended,
                onChanged: (v) => setD(() => ended = v),
              ),
          ]),
        ),
        actions: [
          if (src != null)
            TextButton(
              onPressed: () {
                Haptics.warn();
                s.removeRec('incomes', src, 'Deleted income ${src['name']}');
                Navigator.pop(ctx);
              },
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final n = name.text.trim();
              final v = num.tryParse(amount.text.trim().replaceAll(',', ''));
              if (n.isEmpty || v == null || v <= 0) {
                Haptics.reject();
                return;
              }
              final fields = <String, dynamic>{
                'name': n, 'kind': kind, 'amount': v, 'start': start,
                'end': ended ? ((src?['end'] as String?) ?? Rent.key(now)) : null,
              };
              if (src == null) {
                final rec = <String, dynamic>{'id': s.nextId(), ...fields};
                s.list('incomes').add(rec);
                s.logAction('New income: $n', [{'op': 'rm', 'col': 'incomes', 'id': rec['id']}]);
                s.save();
              } else {
                await s.updateRec('incomes', src, 'Edited income: $n', (r) => r.addAll(fields));
              }
              Haptics.success();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
