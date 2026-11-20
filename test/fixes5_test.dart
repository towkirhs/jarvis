import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/brain.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/local_parser.dart';
import 'package:jarcis/media_page.dart';
import 'package:jarcis/rule_runner.dart';
import 'package:jarcis/rules.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('"turn off all alarms" turns them off on the phone, with Undo', () async {
    expect(LocalParser.moneyCommand('Turn off all alarm')?['type'], 'alarms_off');
    expect(LocalParser.moneyCommand('cancel all my alarms')?['type'], 'alarms_off');
    expect(LocalParser.moneyCommand('turn off the alarm at 7'), isNull);
    final s = await _store();
    s.list('clocks').addAll([
      {'id': 1, 'on': true, 'time': '06:00', 'days': [1]},
      {'id': 2, 'on': true, 'time': '07:00', 'days': [2]},
    ]);
    await Brain.capture(s, 'Turn off all alarm');
    expect(s.list('clocks').where((c) => c['on'] == true), isEmpty);
    expect(s.list('captures').last['msg'], contains('Turned off 2 alarms'));
    await s.undo(s.list('actions').last['id'] as int);
    expect(s.list('clocks').where((c) => c['on'] == true), hasLength(2));
  });

  test('an answer saying alarms "have been turned off" without doing it is caught', () {
    expect(Brain.claimsAction('All alarms have been turned off.'), isTrue);
    expect(Brain.claimsAction("I've switched off your alarm."), isTrue);
  });

  test('a money goal from ChatGPT, dated 15 days before the Eid countdown', () async {
    final s = await _store();
    await s.addCountdown('Eid', '2027-03-22', 'countdown');
    await Brain.capture(s, 'JARVIS v1 {"reply":"Goal set.","items":[{"type":"goal","title":"Eid","amount":20000,"countdown":"Eid","daysBefore":15}]}');
    final g = s.list('goals').single;
    expect([g['name'], g['target'], DateTime.fromMillisecondsSinceEpoch(g['due'] as int)], ['Eid', 20000, DateTime(2027, 3, 7)]);
    expect(s.list('countdowns'), hasLength(1));
  });

  test('a movie from the chat lands in Movies and books, and again updates it', () async {
    final s = await _store();
    await Brain.capture(s, 'JARVIS v1 {"reply":"Noted.","items":[{"type":"media","title":"Inception","category":"movie","status":"done","rating":4}]}');
    await Brain.capture(s, 'JARVIS v1 {"reply":"Noted.","items":[{"type":"media","title":"inception","category":"movie","status":"done","rating":5}]}');
    final m = s.list('media').single;
    expect([m['title'], m['status'], m['rating']], ['inception', 'done', 5]);
  });

  test('a loan paid by bKash comes out of bKash with the built-in link', () async {
    final s = await _store();
    s.list('accounts').add({'id': 77, 'name': 'bKash', 'group': 'Other', 'initial': 0});
    final rule = Rules.builtins().firstWhere((r) => r['builtin'] == 'loanGave')..['id'] = -102;
    rule['on'] = true;
    RuleRunner.fire(s, rule, RuleEvent('loan', {'loanType': 'gave', 'amount': 500, 'person': 'Rafi', 'method': 'bKash', 'title': ''}));
    expect(s.list('tx').single['account'], 'bKash');
  });

  testWidgets('Movies and books fits a phone and adds one', (t) async {
    final s = await _store();
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: MediaPage(store: s)));
    await t.tap(find.byTooltip('Add'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'Dune');
    await t.tap(find.text('Book'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(s.list('media').single['kind'], 'book');
    expect(find.text('Dune'), findsOneWidget);
  });
}
