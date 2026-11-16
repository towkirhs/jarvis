import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/money.dart';
import 'package:jarcis/rent.dart';
import 'package:jarcis/rent_more.dart';
import 'package:jarcis/rent_page.dart';
import 'package:jarcis/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Store> _store(WidgetTester t) async {
  Haptics.on = false;
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (_) async => null);
  final s = Store();
  await s.load();
  t.view.physicalSize = const Size(360, 720);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final now = DateTime.now();
  final last = Rent.key(DateTime(now.year, now.month - 1));
  s.list('rooms').add({'id': 1, 'number': '2A', 'tenant': 'Karim Uddin', 'rent': 5000, 'advance': 0, 'start': last, 'opening': 0});
  s.list('roomBills').add({'id': 2, 'room': 1, 'month': last, 'kind': 'electricity', 'amount': 100, 'from': 200, 'to': 210, 'rate': 10});
  s.list('rentPays').add({'id': 3, 'room': 1, 'amount': 2000, 'paidAt': now.millisecondsSinceEpoch, 'method': 'bKash'});
  return s;
}

void main() {
  testWidgets('Money has an Income tab: rent, loans and salaries add up, and Received puts a salary into Money', (t) async {
    final s = await _store(t);
    final now = DateTime.now();
    s.list('incomes').add({'id': 10, 'name': 'Rafi tuition', 'kind': 'tuition', 'amount': 3000, 'start': Rent.key(DateTime(now.year, now.month - 2))});
    await t.pumpWidget(MaterialApp(home: MoneyPage(store: s)));
    await t.pumpAndSettle();
    expect(find.text('Calendar'), findsNothing); // folded into Stats
    await t.tap(find.text('Stats'));
    await t.pumpAndSettle();
    expect(find.text('Month by month'), findsOneWidget);
    await t.tap(find.text('Month by month'));
    await t.pumpAndSettle();

    await t.ensureVisible(find.widgetWithText(Tab, 'Income'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(Tab, 'Income'));
    await t.pumpAndSettle();
    expect(find.text('What comes in'), findsOneWidget);
    expect(find.text('Rooms and rent'), findsOneWidget);
    expect(find.text('Loans and debts'), findsOneWidget);
    expect(find.textContaining('not received yet (2 months)'), findsOneWidget);

    await t.tap(find.text('Received'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(s.list('incomePays').single['amount'], 3000);
    final tx = s.list('tx').single;
    expect(tx['type'], 'income');
    expect(tx['cat'], 'Tuition');
    expect(find.textContaining('not received yet (1 month)'), findsOneWidget);
  });

  testWidgets('rent: dues can be counted up to last month, and meter readings work out a bill', (t) async {
    final s = await _store(t);
    await t.pumpWidget(MaterialApp(home: RentPage(store: s)));
    await t.pumpAndSettle();
    // Two months of rent and last month's electricity, less 2000 paid.
    expect(find.textContaining('8,100'), findsWidgets);
    await t.tap(find.byTooltip('Count dues up to'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('(last month)'));
    await t.pumpAndSettle();
    expect(find.textContaining('3,000'), findsWidgets);

    await t.tap(find.text('Room 2A'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add bills'));
    await t.pumpAndSettle();
    final to = find.widgetWithText(TextField, 'To').at(1); // water
    await t.ensureVisible(to);
    await t.enterText(find.widgetWithText(TextField, 'From').at(1), '50');
    await t.enterText(to, '58');
    await t.enterText(find.widgetWithText(TextField, 'A unit').at(1), '25');
    await t.pumpAndSettle();
    await t.tap(find.text('Save bills'));
    await t.pumpAndSettle();
    final water = s.list('roomBills').firstWhere((b) => b['kind'] == 'water');
    expect(water['amount'], 200);
    expect(water['to'], 58);
    // The electricity bill kept its readings.
    expect(s.list('roomBills').firstWhere((b) => b['kind'] == 'electricity')['to'], 210);
  });

  testWidgets('the receipt is laid out like a rent receipt form and fits a phone', (t) async {
    final s = await _store(t);
    s.settings['landlordName'] = 'Towkir';
    await t.pumpWidget(MaterialApp(home: ReceiptPage(store: s, roomId: 1, month: Rent.key(DateTime.now()))));
    await t.pumpAndSettle();
    for (final label in ['Rent Receipt', 'PAYEE INFORMATION', 'PAYER INFORMATION', 'PAYMENT DETAILS', 'IMPORTANT NOTES', 'SIGNATURE:']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Karim Uddin'), findsOneWidget);
    expect(find.textContaining('200 to 210'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Print or save as PDF'), 200);
  });
}
