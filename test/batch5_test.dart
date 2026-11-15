import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/decide.dart';
import 'package:jarcis/destination.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/home_screen.dart';
import 'package:jarcis/money.dart';
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
  return s;
}

void main() {
  test('chat keywords: decide:, decided:, promise: (with a colon only)', () {
    expect(Destination.of('decide: tea or coffee')?.type, 'decide');
    expect(Destination.of('decide: tea or coffee')?.rest, 'tea or coffee');
    expect(Destination.of('Decided: take the job because it pays more')?.type, 'decision');
    expect(Destination.of('promise: send Rahim the notes')?.type, 'promise');
    expect(Destination.of('decide later about the trip'), isNull);
    final forced = Destination.force({'items': <dynamic>[]}, Destination.of('promise: call Mom')!);
    expect((forced['items'] as List).single, {'type': 'promise', 'title': 'call Mom', 'confidence': 1, 'asked': true});
  });

  test('decision options come from "A or B" and lists, else the AI names them', () {
    expect(Decide.options('tea or coffee'), ['tea', 'coffee']);
    expect(Decide.options('Should I take the bus, a rickshaw or walk?'), ['take the bus', 'a rickshaw', 'walk']);
    expect(Decide.options('should I quit my job'), isEmpty);
  });

  test('nudges: any number, or no limit', () async {
    SharedPreferences.setMockInitialValues({});
    final s = Store();
    await s.load();
    s.settings['cap'] = 30;
    expect(s.cap, 30);
    s.settings['cap'] = 0;
    expect(s.cap, greaterThan(100000));
  });

  testWidgets('a decision in the chat shows each option with its odds', (t) async {
    final s = await _store(t);
    s.list('captures').add({
      'id': 1, 'raw': 'decide: tea or coffee', 'status': 'done', 'ts': DateTime.now().millisecondsSinceEpoch,
      'reply': 'tea (70%). coffee 30%', 'via': 'ai',
      'decision': [
        {'id': 'pick', 'type': 'choice', 'probs': {'tea': 0.7, 'coffee': 0.3}},
        {'id': 'impact', 'type': 'score', 'probs': {'1': 0.8, '2': 0.2}},
      ],
    });
    await t.pumpWidget(MaterialApp(home: Scaffold(body: HomeScreen(store: s))));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('70%'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    expect(find.textContaining('decide fast and move on'), findsOneWidget);
  });

  testWidgets('Money on a phone: Stats and Goals lay out, and a goal can be made', (t) async {
    final s = await _store(t);
    final now = DateTime.now();
    for (var k = 0; k < 6; k++) {
      s.addTx(type: 'income', amount: 30000, category: 'Salary', account: 'Cash', ts: DateTime(now.year, now.month - k, 1, 10).millisecondsSinceEpoch);
      s.addTx(type: 'expense', amount: 9000 + k * 500, category: k.isEven ? 'Food' : 'Transport', account: 'Cash',
          ts: DateTime(now.year, now.month - k, 1, 12).millisecondsSinceEpoch);
    }
    s.list('accounts').add({'id': 77, 'name': 'DPS', 'group': 'Bank', 'initial': 50000, 'savings': true});
    await t.pumpWidget(MaterialApp(home: MoneyPage(store: s)));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Stats'));
    await t.pumpAndSettle();
    await t.tap(find.text('Stats'));
    await t.pumpAndSettle();
    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Last 6 months'), findsOneWidget);
    await t.scrollUntilVisible(find.text('What you have'), 200, scrollable: find.byType(Scrollable).at(1));

    await t.ensureVisible(find.text('Goals'));
    await t.pumpAndSettle();
    await t.tap(find.text('Goals'));
    await t.pumpAndSettle();
    expect(find.text('Long-term savings'), findsOneWidget);
    await t.tap(find.text('Goal'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'What for, like Laptop'), 'Laptop');
    await t.enterText(find.widgetWithText(TextField, 'Amount you need'), '100000');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(s.list('goals').single['name'], 'Laptop');
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
  });
}
