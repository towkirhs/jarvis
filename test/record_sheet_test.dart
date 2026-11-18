import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/day_page.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/pages.dart';
import 'package:jarcis/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Store> _store() async {
  Haptics.on = false;
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (call) async => null);
  final s = Store();
  await s.load();
  return s;
}

Future<void> _phone(WidgetTester t) async {
  t.view.physicalSize = const Size(360, 720);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a decision can be changed, copied and deleted on a phone screen', (t) async {
    final s = await _store();
    s.list('decisions').add({'id': 1, 'decision': 'Take the bus', 'reason': 'cheaper', 'ts': DateTime(2026, 11, 18, 9).millisecondsSinceEpoch});
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    await _phone(t);
    await t.pumpWidget(MaterialApp(home: DecisionsPage(store: s)));
    await t.tap(find.text('Take the bus'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Take the bus'), 'Take the train');
    await t.tap(find.text('Copy'));
    await t.pumpAndSettle();
    expect(copied, contains('Decision: Take the train'));
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(s.list('decisions').single['decision'], 'Take the train');

    await t.tap(find.text('Take the train'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(s.list('decisions'), isEmpty);
  });

  testWidgets('a promise and a Your day line open the same editor', (t) async {
    final s = await _store();
    s.list('promises').add({'id': 2, 'person': 'Oishi', 'what': 'Call her mother', 'status': 'open', 'due': null});
    s.list('log').add({'id': 3, 'at': DateTime.now().millisecondsSinceEpoch, 'kind': 'now', 'verb': 'start', 'text': 'Started gym'});
    await _phone(t);
    await t.pumpWidget(MaterialApp(home: PromisesPage(store: s)));
    await t.tap(find.text('Oishi: Call her mother'));
    await t.pumpAndSettle();
    expect(find.text('Promise'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Call her mother'), 'Call her mother on Friday');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(s.list('promises').single['what'], 'Call her mother on Friday');

    await t.pumpWidget(MaterialApp(home: DayPage(store: s)));
    await t.pumpAndSettle();
    await t.tap(find.text('Started gym'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Started gym'), 'Started the gym');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(s.list('log').single['text'], 'Started the gym');
  });
}
