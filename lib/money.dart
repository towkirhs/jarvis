import 'dart:math';

import 'package:flutter/material.dart';

import 'haptics.dart';
import 'money_io.dart';
import 'money_sms.dart';
import 'native.dart';
import 'store.dart';

const expenseCats = ['Food', 'Transport', 'Shopping', 'Bills', 'Education', 'Health', 'Entertainment', 'Gifts', 'Other'];
const incomeCats = ['Salary', 'Tuition', 'Allowance', 'Gift', 'Other'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _incomeColor = Colors.blue;
const _expenseColor = Colors.redAccent;
const _chartColors = [
  Colors.redAccent, Colors.orange, Colors.amber, Colors.green, Colors.teal,
  Colors.blue, Colors.indigo, Colors.purple, Colors.pink, Colors.brown,
];

bool _inMonth(Rec t, DateTime m) {
  final d = fromMs(t['ts'] as int);
  return d.year == m.year && d.month == m.month;
}

/// (income, expense) of the given transactions. Transfers count as neither.
(num, num) _sums(Iterable<Rec> txs) {
  num inc = 0;
  num exp = 0;
  for (final t in txs) {
    if (t['type'] == 'income') inc += t['amount'] as num;
    if (t['type'] == 'expense') exp += t['amount'] as num;
  }
  return (inc, exp);
}

/// Adds a transaction, or edits [tx]. [day] presets the date of a new one.
Future<void> showTxSheet(BuildContext context, Store s, {Rec? tx, DateTime? day}) {
  var type = (tx?['type'] as String?) ?? 'expense';
  var when = tx != null ? fromMs(tx['ts'] as int) : (day ?? DateTime.now());
  final amount = TextEditingController(text: tx == null ? '' : '${tx['amount']}');
  final cat = TextEditingController(text: tx?['cat'] as String? ?? '');
  final note = TextEditingController(text: tx?['note'] as String? ?? '');
  final desc = TextEditingController(text: tx?['desc'] as String? ?? '');
  final tags = TextEditingController(text: ((tx?['tags'] as List?) ?? []).join(', '));
  final accounts = s.list('accounts').map((a) => a['name'] as String).toList();
  var account = (tx?['account'] as String?) ?? (accounts.isEmpty ? 'Cash' : accounts.first);
  var toAccount = (tx?['toAccount'] as String?) ?? (accounts.length > 1 ? accounts[1] : account);
  if (!accounts.contains(account)) accounts.add(account);
  if (!accounts.contains(toAccount)) accounts.add(toAccount);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final color = type == 'income' ? _incomeColor : (type == 'expense' ? _expenseColor : Colors.grey);
      final used = {for (final t in s.list('tx')) if (t['type'] == type) t['cat'] as String};
      final cats = {...(type == 'income' ? incomeCats : expenseCats), ...used}.toList();

      Future<void> save() async {
        final a = num.tryParse(amount.text.trim().replaceAll(',', ''));
        if (a == null || a <= 0) return;
        final fields = <String, dynamic>{
          'type': type,
          'amount': a,
          'cat': type == 'transfer' ? 'Transfer' : (cat.text.trim().isEmpty ? 'Other' : cat.text.trim()),
          'account': account,
          'toAccount': type == 'transfer' ? toAccount : null,
          'note': note.text.trim().isEmpty ? null : note.text.trim(),
          'desc': desc.text.trim().isEmpty ? null : desc.text.trim(),
          'tags': tags.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
          'ts': when.millisecondsSinceEpoch,
        };
        if (tx == null) {
          final undo = <Rec>[];
          s.addTx(
            type: type,
            amount: a,
            category: fields['cat'] as String,
            account: account,
            toAccount: fields['toAccount'] as String?,
            note: fields['note'] as String?,
            desc: fields['desc'] as String?,
            tags: (fields['tags'] as List).cast<String>(),
            ts: when.millisecondsSinceEpoch,
            undo: undo,
          );
          s.logAction('${type[0].toUpperCase()}${type.substring(1)}: ${s.money(a)} ${fields['cat']}', undo);
          s.save();
        } else {
          await s.updateRec('tx', tx, 'Edited ${s.money(a)} ${fields['cat']}', (r) => r.addAll(fields));
        }
        Haptics.tap();
        if (ctx.mounted) Navigator.pop(ctx);
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'income', label: Text('Income')),
                  ButtonSegment(value: 'expense', label: Text('Expense')),
                  ButtonSegment(value: 'transfer', label: Text('Transfer')),
                ],
                selected: {type},
                onSelectionChanged: (v) => setS(() => type = v.first),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text('${dayKey(when)} (${_weekdays[when.weekday - 1]})'),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: when,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setS(() => when = DateTime(d.year, d.month, d.day, when.hour, when.minute));
                    },
                  ),
                  TextButton(
                    child: Text(TimeOfDay.fromDateTime(when).format(ctx)),
                    onPressed: () async {
                      final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(when));
                      if (t != null) setS(() => when = DateTime(when.year, when.month, when.day, t.hour, t.minute));
                    },
                  ),
                ],
              ),
              TextField(
                controller: amount,
                autofocus: tx == null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(fontSize: 26, color: color),
                decoration: InputDecoration(labelText: 'Amount', prefixText: '${s.currency} '),
              ),
              if (type != 'transfer') ...[
                const SizedBox(height: 8),
                TextField(controller: cat, decoration: const InputDecoration(labelText: 'Category', isDense: true)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    for (final c in cats)
                      ChoiceChip(
                        label: Text(c),
                        selected: cat.text == c,
                        onSelected: (_) => setS(() => cat.text = c),
                      ),
                  ],
                ),
              ],
              Row(
                children: [
                  Text(type == 'transfer' ? 'From  ' : 'Account  '),
                  DropdownButton<String>(
                    value: account,
                    items: [for (final a in accounts) DropdownMenuItem(value: a, child: Text(a))],
                    onChanged: (v) => setS(() => account = v ?? account),
                  ),
                  if (type == 'transfer') ...[
                    const Text('   To  '),
                    DropdownButton<String>(
                      value: toAccount,
                      items: [for (final a in accounts) DropdownMenuItem(value: a, child: Text(a))],
                      onChanged: (v) => setS(() => toAccount = v ?? toAccount),
                    ),
                  ],
                ],
              ),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Note', isDense: true)),
              TextField(controller: tags, decoration: const InputDecoration(labelText: 'Tags, comma separated', isDense: true)),
              TextField(
                controller: desc,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description', isDense: true),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (tx != null)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                      onPressed: () {
                        Haptics.warn();
                        s.removeRec('tx', tx, 'Deleted ${s.money(tx['amount'] as num)} ${tx['cat']}');
                        Navigator.pop(ctx);
                      },
                    ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: color),
                    onPressed: save,
                    child: Text(tx == null ? 'Save' : 'Update'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }),
  );
}

const _catIcons = {
  'Food': Icons.restaurant, 'Transport': Icons.directions_bus, 'Shopping': Icons.shopping_bag_outlined,
  'Bills': Icons.receipt_long, 'Education': Icons.school_outlined, 'Health': Icons.medical_services_outlined,
  'Entertainment': Icons.movie_outlined, 'Gifts': Icons.card_giftcard, 'Salary': Icons.work_outline,
  'Tuition': Icons.menu_book_outlined, 'Allowance': Icons.savings_outlined, 'Gift': Icons.card_giftcard,
  'Transfer': Icons.swap_horiz,
};

/// One transaction row: what it was for, category, account and time, amount in colour.
Widget _txRow(BuildContext context, Store s, Rec t) {
  final type = t['type'] as String;
  final color = type == 'income' ? _incomeColor : (type == 'expense' ? _expenseColor : null);
  final cat = t['cat'] as String;
  final sub = [
    if (t['note'] != null) cat,
    type == 'transfer' ? '${t['account']} → ${t['toAccount']}' : t['account'] as String,
    clock(t['ts'] as int),
    ...((t['tags'] as List?) ?? []).map((e) => '#$e'),
  ].join('  ·  ');
  return ListTile(
    onTap: () => showTxSheet(context, s, tx: t),
    leading: CircleAvatar(
      backgroundColor: (color ?? Colors.grey).withValues(alpha: 0.15),
      child: Icon(_catIcons[cat] ?? Icons.category_outlined, color: color ?? Colors.grey, size: 20),
    ),
    title: Text((t['note'] as String?) ?? cat, overflow: TextOverflow.ellipsis),
    subtitle: Text(sub, overflow: TextOverflow.ellipsis),
    trailing: Text(
      '${type == 'expense' ? '-' : (type == 'income' ? '+' : '')}${s.money(t['amount'] as num)}',
      style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w600),
    ),
  );
}

class MoneyPage extends StatefulWidget {
  const MoneyPage({super.key, required this.store});
  final Store store;

  @override
  State<MoneyPage> createState() => _MoneyPageState();
}

class _MoneyPageState extends State<MoneyPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _calDay;

  Store get s => widget.store;

  void _shift(int by) => setState(() {
        _month = DateTime(_month.year, _month.month + by);
        _calDay = null;
      });

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 5,
        child: Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(tooltip: 'Previous', icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
                Text('${_months[_month.month - 1]} ${_month.year}'),
                IconButton(tooltip: 'Next', icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Log money automatically',
                icon: const Icon(Icons.bolt),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AutoMoneyPage(store: s))),
              ),
              PopupMenuButton<String>(
                tooltip: 'Export and import',
                icon: const Icon(Icons.import_export),
                onSelected: (v) => _io(context, v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'month-csv', child: Text('Export this month (CSV)')),
                  PopupMenuItem(value: 'month-xlsx', child: Text('Export this month (Excel)')),
                  PopupMenuItem(value: 'all-csv', child: Text('Export everything (CSV)')),
                  PopupMenuItem(value: 'all-xlsx', child: Text('Export everything (Excel)')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'import', child: Text('Import CSV or Excel')),
                ],
              ),
            ],
            bottom: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [Tab(text: 'Daily'), Tab(text: 'Calendar'), Tab(text: 'Monthly'), Tab(text: 'Stats'), Tab(text: 'Accounts')],
            ),
          ),
          floatingActionButton: Builder(builder: (context) {
            final tabs = DefaultTabController.of(context);
            return ListenableBuilder(
              listenable: tabs,
              builder: (context, _) => tabs.index == 4
                  ? FloatingActionButton.extended(
                      onPressed: () => _editAccount(context, null),
                      icon: const Icon(Icons.add),
                      label: const Text('Account'),
                    )
                  : FloatingActionButton(
                      onPressed: () => showTxSheet(context, s, day: _calDay),
                      child: const Icon(Icons.add),
                    ),
            );
          }),
          body: ListenableBuilder(
            listenable: s,
            builder: (context, _) {
              final monthTx = s.list('tx').where((t) => _inMonth(t, _month)).toList()
                ..sort((a, b) => (b['ts'] as int).compareTo(a['ts'] as int));
              final (inc, exp) = _sums(monthTx);
              return Column(
                children: [
                  _summary(context, inc, exp),
                  const Divider(height: 1),
                  Expanded(
                    child: TabBarView(
                      // Sideways swipes switch the app's main tabs; these tabs switch by tapping.
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _daily(context, monthTx),
                        _calendar(context, monthTx),
                        _monthly(context),
                        _stats(context, monthTx),
                        _accounts(context),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );

  Future<void> _io(BuildContext context, String v) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (v == 'import') {
        final r = await MoneyIO.import(s);
        if (r == null) return;
        messenger.showSnackBar(SnackBar(content: Text('Imported ${r.$1} transactions, skipped ${r.$2} (duplicates or unreadable).')));
        return;
      }
      final all = v.startsWith('all');
      final txs = s.list('tx').where((t) => all || _inMonth(t, _month)).toList()
        ..sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));
      final name = all ? 'jarvis-money' : 'jarvis-money-${_month.year}-${two(_month.month)}';
      final ok = await MoneyIO.export(s, txs, xlsx: v.endsWith('xlsx'), name: name);
      if (ok) messenger.showSnackBar(SnackBar(content: Text('Exported ${txs.length} transactions.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not do that: $e')));
    }
  }

  Widget _summary(BuildContext context, num inc, num exp) {
    Widget col(String label, num v, Color? c) => Expanded(
          child: Column(children: [
            Text(label),
            Text(s.money(v), style: TextStyle(fontSize: 17, color: c)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        col('Income', inc, _incomeColor),
        col('Expenses', exp, _expenseColor),
        col('Total', inc - exp, null),
      ]),
    );
  }

  Widget _empty() => const Center(child: Text('No data. Tap + or tell Jarvis "spent 200 on lunch".'));

  Widget _daily(BuildContext context, List<Rec> txs) {
    if (txs.isEmpty) return _empty();
    final days = <String, List<Rec>>{};
    for (final t in txs) {
      days.putIfAbsent(dayKey(fromMs(t['ts'] as int)), () => []).add(t);
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        for (final e in days.entries) ...[
          Container(
            color: Theme.of(context).colorScheme.surfaceContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Text(
                '${DateTime.parse(e.key).day}  ${_weekdays[DateTime.parse(e.key).weekday - 1]}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(s.money(_sums(e.value).$1), style: const TextStyle(color: _incomeColor)),
              const SizedBox(width: 16),
              Text(s.money(_sums(e.value).$2), style: const TextStyle(color: _expenseColor)),
            ]),
          ),
          for (final t in e.value) _txRow(context, s, t),
        ],
      ],
    );
  }

  Widget _calendar(BuildContext context, List<Rec> txs) {
    final first = DateTime(_month.year, _month.month, 1);
    final daysIn = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday - 1;
    final scheme = Theme.of(context).colorScheme;
    final selected = _calDay == null ? null : dayKey(_calDay!);
    final dayTx = selected == null ? <Rec>[] : txs.where((t) => dayKey(fromMs(t['ts'] as int)) == selected).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 80),
      children: [
        Row(children: [for (final w in _weekdays) Expanded(child: Center(child: Text(w, style: const TextStyle(fontSize: 12))))]),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.8,
          children: [
            for (var i = 0; i < lead; i++) const SizedBox(),
            for (var d = 1; d <= daysIn; d++)
              Builder(builder: (context) {
                final day = DateTime(_month.year, _month.month, d);
                final (inc, exp) = _sums(txs.where((t) => dayKey(fromMs(t['ts'] as int)) == dayKey(day)));
                return InkWell(
                  onTap: () => setState(() => _calDay = day),
                  child: Container(
                    margin: const EdgeInsets.all(1),
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      border: Border.all(color: dayKey(day) == selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$d', style: TextStyle(fontSize: 12, fontWeight: dayKey(day) == dayKey(DateTime.now()) ? FontWeight.bold : null)),
                        const Spacer(),
                        if (inc > 0) Text(_short(inc), style: const TextStyle(fontSize: 10, color: _incomeColor)),
                        if (exp > 0) Text(_short(exp), style: const TextStyle(fontSize: 10, color: _expenseColor)),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
        if (selected != null) ...[
          Padding(padding: const EdgeInsets.all(8), child: Text(selected, style: const TextStyle(fontWeight: FontWeight.bold))),
          if (dayTx.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Nothing on this day.')),
          for (final t in dayTx) _txRow(context, s, t),
        ],
      ],
    );
  }

  /// Short amount for small calendar cells: 1.2k, 35, 2.5M.
  String _short(num v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
  }

  Widget _monthly(BuildContext context) {
    final months = [for (var i = 0; i < 12; i++) DateTime(_month.year, _month.month - i)];
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        for (final m in months)
          Builder(builder: (context) {
            final (inc, exp) = _sums(s.list('tx').where((t) => _inMonth(t, m)));
            return ListTile(
              title: Text('${_months[m.month - 1]} ${m.year}'),
              subtitle: Text('Total ${s.money(inc - exp)}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(s.money(inc), style: const TextStyle(color: _incomeColor)),
                  Text(s.money(exp), style: const TextStyle(color: _expenseColor)),
                ],
              ),
              onTap: () => setState(() => _month = m),
            );
          }),
      ],
    );
  }

  Widget _stats(BuildContext context, List<Rec> txs) {
    final byCat = <String, num>{};
    for (final t in txs.where((t) => t['type'] == 'expense')) {
      byCat.update(t['cat'] as String, (v) => v + (t['amount'] as num), ifAbsent: () => t['amount'] as num);
    }
    if (byCat.isEmpty) return _empty();
    final entries = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<num>(0, (a, e) => a + e.value);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        const Center(child: Text('Expenses by category')),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: CustomPaint(
            painter: _DonutPainter([for (final e in entries) e.value.toDouble()]),
            child: Center(child: Text(s.money(total), style: const TextStyle(fontSize: 18))),
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < entries.length; i++)
          ListTile(
            dense: true,
            leading: Container(
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _chartColors[i % _chartColors.length], borderRadius: BorderRadius.circular(4)),
              child: Text('${(entries[i].value / total * 100).round()}%', style: const TextStyle(color: Colors.white)),
            ),
            title: Text(entries[i].key),
            trailing: Text(s.money(entries[i].value)),
          ),
      ],
    );
  }

  Widget _accounts(BuildContext context) {
    final accts = s.list('accounts');
    final total = accts.fold<num>(0, (a, acc) => a + s.balance(acc));
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        // What you have in all, as the headline of the page.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Total balance', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(s.money(total), style: Theme.of(context).textTheme.displaySmall?.copyWith(color: total < 0 ? _expenseColor : null)),
          ]),
        ),
        const Divider(height: 1),
        for (final a in accts)
          ListTile(
            title: Text(a['name'] as String),
            // Skip the type when it only repeats the name ("Cash / Cash").
            subtitle: (a['group'] as String? ?? '').isEmpty || a['group'] == a['name'] ? null : Text(a['group'] as String),
            trailing: Text(
              s.money(s.balance(a)),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: s.balance(a) < 0 ? _expenseColor : null),
            ),
            onTap: () => _editAccount(context, a),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add account'),
            onPressed: () => _editAccount(context, null),
          ),
        ),
      ],
    );
  }

  Future<void> _editAccount(BuildContext context, Rec? a) async {
    final name = TextEditingController(text: a?['name'] as String? ?? '');
    final group = TextEditingController(text: a?['group'] as String? ?? 'Cash');
    final initial = TextEditingController(text: '${a?['initial'] ?? 0}');
    String? nameError;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: Text(a == null ? 'New account' : 'Edit account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: a == null,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Name, like Rocket or City Bank', errorText: nameError),
            ),
            const SizedBox(height: 12),
            TextField(controller: group, decoration: const InputDecoration(labelText: 'Group, like Cash, Bank, Card')),
            const SizedBox(height: 12),
            TextField(
              controller: initial,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(labelText: 'Starting balance', prefixText: '${s.currency} '),
            ),
          ],
        ),
        actions: [
          if (a != null)
            TextButton(
              onPressed: () {
                Haptics.warn();
                s.removeRec('accounts', a, 'Deleted account ${a['name']}');
                Navigator.pop(ctx);
              },
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final n = name.text.trim();
              if (n.isEmpty) return setD(() => nameError = Haptics.rejected() ?? 'Give the account a name');
              if (s.list('accounts').any((x) => x != a && (x['name'] as String).toLowerCase() == n.toLowerCase())) {
                return setD(() => nameError = Haptics.rejected() ?? 'You already have an account called $n');
              }
              final start = num.tryParse(initial.text.trim()) ?? 0;
              if (a == null) {
                final r = {'id': s.nextId(), 'name': n, 'group': group.text.trim(), 'initial': start};
                s.list('accounts').add(r);
                s.logAction('Added account $n', [
                  {'op': 'rm', 'col': 'accounts', 'id': r['id']},
                ]);
                s.save();
              } else {
                final old = a['name'];
                await s.updateRec('accounts', a, 'Edited account $n', (r) {
                  r['name'] = n;
                  r['group'] = group.text.trim();
                  r['initial'] = start;
                });
                // Keep transactions pointing at the renamed account.
                for (final t in s.list('tx')) {
                  if (t['account'] == old) t['account'] = n;
                  if (t['toAccount'] == old) t['toAccount'] = n;
                }
                s.save();
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      )),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    final r = min(size.width, size.height) / 2 - 10;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    var start = -pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * pi;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 34
        ..color = _chartColors[i % _chartColors.length];
      canvas.drawArc(rect, start, sweep, false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => true;
}

/// Reads waiting bKash/Nagad/bank messages into transactions. Skips ones already logged
/// (same TrxID, or the same amount within 10 minutes when there is no TrxID). Returns how many were added.
Future<int> drainMoneyQueue(Store s) async {
  var added = 0;
  for (final (from, text, ts) in await Native.takeMoney()) {
    final e = MoneySms.parse(text, from: from, now: fromMs(ts));
    if (e == null) continue;
    final dup = s.list('tx').any((t) => e.trxId != null
        ? t['trxId'] == e.trxId
        : t['auto'] == true &&
            t['type'] == e.type &&
            t['amount'] == e.amount &&
            ((t['ts'] as int) - e.ts.millisecondsSinceEpoch).abs() < 10 * 60000);
    if (dup) continue;
    final undo = <Rec>[];
    for (final name in [e.account, if (e.toAccount != null) e.toAccount!]) {
      if (s.list('accounts').every((a) => a['name'] != name)) {
        final a = {'id': s.nextId(), 'name': name, 'group': name == 'Cash' ? 'Cash' : (name == 'Bank' ? 'Bank' : 'Mobile wallet'), 'initial': 0};
        s.list('accounts').add(a);
        undo.add({'op': 'rm', 'col': 'accounts', 'id': a['id']});
      }
    }
    final r = s.addTx(
      type: e.type,
      amount: e.amount,
      category: e.category,
      account: e.account,
      toAccount: e.toAccount,
      note: e.note,
      ts: e.ts.millisecondsSinceEpoch,
      undo: undo,
    );
    r['auto'] = true;
    r['trxId'] = e.trxId;
    r['needsLabel'] = e.type != 'transfer' && e.category == 'Other';
    s.logAction('Logged from ${e.account}: ${s.money(e.amount)} ${e.note ?? e.category}', undo);
    added++;
  }
  if (added > 0) s.save();
  return added;
}

/// "What was this for?" for transactions logged automatically from messages.
class LabelCard extends StatelessWidget {
  const LabelCard({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    final s = store;
    final todo = s.list('tx').where((t) => t['needsLabel'] == true).toList();
    if (todo.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('What were these for?', style: TextStyle(fontWeight: FontWeight.bold)),
            for (final t in todo.take(3)) ...[
              const SizedBox(height: 8),
              Text('${t['type'] == 'income' ? '+' : '-'}${s.money(t['amount'] as num)}  ${t['note'] ?? ''}  ·  ${t['account']}  ·  ${niceWhen(t['ts'] as int)}'),
              Wrap(
                spacing: 6,
                children: [
                  for (final c in t['type'] == 'income' ? incomeCats : expenseCats)
                    ActionChip(
                      label: Text(c),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => s.updateRec('tx', t, 'Labelled ${s.money(t['amount'] as num)} as $c', (r) {
                        r['cat'] = c;
                        r['needsLabel'] = false;
                      }),
                    ),
                ],
              ),
            ],
            if (todo.length > 3) Text('and ${todo.length - 3} more', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Turns automatic logging on: SMS permission and notification access.
class AutoMoneyPage extends StatefulWidget {
  const AutoMoneyPage({super.key, required this.store});
  final Store store;

  @override
  State<AutoMoneyPage> createState() => _AutoMoneyPageState();
}

class _AutoMoneyPageState extends State<AutoMoneyPage> with WidgetsBindingObserver {
  ({bool sms, bool notifications}) _access = (sms: false, notifications: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from Android's settings page: check again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final a = await Native.moneyAccess();
    if (mounted) setState(() => _access = a);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Log money automatically')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Jarvis can read transaction messages from bKash, Nagad, Rocket and your bank, and log them for you. '
              'Cash in and cash out become transfers. When it can\'t tell what a payment was for, it asks you on Home.\n\n'
              'Messages are read on this phone only. Only messages with an amount (Tk, BDT, ৳) are kept; OTPs and offers are ignored.',
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: Icon(_access.sms ? Icons.check_circle : Icons.sms_outlined, color: _access.sms ? Colors.green : null),
                title: const Text('Read transaction SMS'),
                subtitle: Text(_access.sms ? 'On' : 'Off. Tap to allow.'),
                onTap: _access.sms
                    ? null
                    : () async {
                        await Native.requestSmsPermission();
                        await Future<void>.delayed(const Duration(seconds: 1));
                        _refresh();
                      },
              ),
            ),
            Card(
              child: ListTile(
                leading: Icon(_access.notifications ? Icons.check_circle : Icons.notifications_outlined,
                    color: _access.notifications ? Colors.green : null),
                title: const Text('Read wallet and bank app notifications'),
                subtitle: Text(_access.notifications
                    ? 'On'
                    : 'Off. Tap, then turn on "Jarvis money logging" in the list Android shows.'),
                onTap: _access.notifications ? null : Native.openNotificationAccess,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Logged: ${widget.store.list('tx').where((t) => t['auto'] == true).length} transactions so far.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
}
