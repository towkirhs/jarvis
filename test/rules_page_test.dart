import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/rules_page.dart';
import 'package:jarcis/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('links can be switched on, and a new rule can be made', (t) async {
    Haptics.on = false;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (_) async => null);
    final s = Store();
    await s.load();
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: RulesPage(store: s)));
    await t.pumpAndSettle();

    expect(find.text('Rent goes into Money'), findsOneWidget);
    await t.tap(find.text('Rent goes into Money'));
    await t.pumpAndSettle();
    expect(s.list('rules').firstWhere((r) => r['builtin'] == 'rent')['on'], true);

    await t.tap(find.text('Rule'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Name'), 'Cream');
    await t.enterText(find.widgetWithText(TextFormField, 'Reminder'), 'Buy Duaris cream');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final r = s.list('rules').firstWhere((r) => r['name'] == 'Cream');
    expect(r['when'], {'on': 'money'});
    expect(r['then'], [{'do': 'remind', 'text': 'Buy Duaris cream'}]);
    expect(find.textContaining('remind me: Buy Duaris cream'), findsOneWidget);
  });
}
