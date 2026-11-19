import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/budgets.dart';
import 'package:jarcis/day_log.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/money_plan.dart';
import 'package:jarcis/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Store> _store() async {
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (_) async => null);
  Haptics.on = false;
  final s = Store();
  await s.load();
  return s;
}

Map<String, dynamic> _tx(String cat, num amount, DateTime at) => {'type': 'expense', 'cat': cat, 'amount': amount, 'ts': at.millisecondsSinceEpoch};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 19, 12);

  test('budgets: spent this month only, fullest first; warnings at 80% and over', () {
    final tx = [_tx('Food', 3000, now), _tx('Food', 900, DateTime(2026, 10, 30)), _tx('Transport', 200, now)];
    final rows = Budgets.month(tx, {'Food': 4000, 'Transport': 1000}, now);
    expect([for (final r in rows) '${r.category} ${r.spent} ${r.left}'], ['Food 3000 1000', 'Transport 200 800']);
    tx.add(_tx('Food', 300, now));
    expect(Budgets.crossed(tx, {'Food': 4000}, 'Food', 300, now), contains('83%'));
    tx.add(_tx('Food', 800, now));
    expect(Budgets.crossed(tx, {'Food': 4000}, 'Food', 800, now), contains('over its budget'));
    expect(Budgets.crossed(tx, {'Food': 4000}, 'Transport', 100, now), isNull);
  });

  test('to buy: open tasks with a price or starting with "buy"', () {
    final items = [
      {'kind': 'task', 'status': 'open', 'title': 'Buy milk'},
      {'kind': 'task', 'status': 'open', 'title': 'Lotion', 'cost': 450},
      {'kind': 'task', 'status': 'done', 'title': 'Buy bread', 'cost': 60},
      {'kind': 'task', 'status': 'open', 'title': 'Call Naomi'},
    ];
    expect(Budgets.toBuy(items).map((i) => i['title']), ['Lotion', 'Buy milk']);
  });

  test('ticking off a task that costs money offers "Paid?", and paying logs the expense once, with Undo', () async {
    final s = await _store();
    final it = {'id': 5, 'kind': 'task', 'status': 'open', 'title': 'Buy lotion', 'cost': 450};
    s.list('items').add(it);
    await s.markDone(it);
    expect(s.moneyNotice.value?.text, 'Paid ৳450 for Buy lotion?');
    s.payFor(it);
    s.payFor(it);
    final tx = s.list('tx').single;
    expect([tx['amount'], tx['account'], tx['type']], [450, 'Cash', 'expense']);
    await s.undo(s.list('actions').last['id'] as int);
    expect(s.list('tx'), isEmpty);
    expect(s.byId('items', 5)!['paidTx'], isNull);
  });

  test('an expense that crosses 80% of a budget says so', () async {
    final s = await _store();
    await s.setBudget('Food', 1000);
    s.addTx(type: 'expense', amount: 500, category: 'Food', account: 'Cash');
    expect(s.moneyNotice.value, isNull);
    s.addTx(type: 'expense', amount: 350, category: 'Food', account: 'Cash');
    expect(s.moneyNotice.value?.text, contains('85%'));
  });

  test('money shows on the Your day timeline', () {
    final m = DayLog.timeline(now, log: const [], items: const [], tx: [
      {'type': 'expense', 'cat': 'Food', 'note': 'Juice', 'amount': 630, 'ts': now.millisecondsSinceEpoch},
    ]);
    expect(m.single.text, 'Spent ৳630 · Food · Juice');
    expect(m.single.kind, 'money');
  });

  testWidgets('the To buy and Budgets cards fit a phone', (t) async {
    final s = await _store();
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    s.list('items').add({'id': 5, 'kind': 'task', 'status': 'open', 'title': 'Buy a very long named moisturising lotion for winter', 'cost': 450});
    await s.setBudget('Food', 1000);
    s.addTx(type: 'expense', amount: 900, category: 'Food', account: 'Cash');
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: MoneyPlanCards(store: s)))));
    await t.pumpAndSettle();
    expect(find.text('To buy · 1'), findsOneWidget);
    expect(find.text('Budgets this month'), findsOneWidget);
    expect(find.textContaining('100 left'), findsOneWidget);
  });
}
