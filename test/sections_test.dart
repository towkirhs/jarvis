import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/data_page.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/sections.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a section goes out as text and comes back in next to what is there, without doubles', () async {
    final a = await _store();
    await a.addHabit('Read', 7);
    a.addTx(type: 'expense', amount: 50, category: 'Food', account: 'Cash');
    a.list('accounts').add({'id': 900, 'name': 'Oishi', 'group': 'Other', 'initial': 0});
    final habits = a.exportSection(Sections.byKey('habits')!);
    final money = a.exportSection(Sections.byKey('money')!);
    expect(Sections.parse(habits).$1.name, 'Habits');
    expect(() => Sections.parse('{"x": 1}'), throwsFormatException);

    final b = await _store();
    await b.addHabit('Walk', 7);
    expect((await b.importSection(habits)).$2, 1);
    expect(b.list('habits').map((h) => h['name']), ['Walk', 'Read']);
    expect((await b.importSection(habits)).$2, 0); // already there

    final (_, n) = await b.importSection(money);
    expect(b.list('accounts').where((x) => x['name'] == 'Oishi'), hasLength(1)); // Cash, Bank… matched by name
    expect(b.list('tx'), hasLength(1));
    expect(n, 2);
    await b.undo(b.list('actions').last['id'] as int);
    expect(b.list('tx'), isEmpty);
    expect(b.list('accounts').where((x) => x['name'] == 'Oishi'), isEmpty);
  });

  testWidgets('Move data fits a phone and lists every part with its size', (t) async {
    final s = await _store();
    await s.addHabit('Read', 7);
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: DataPage(store: s)));
    await t.pumpAndSettle();
    expect(find.text('Habits'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Add from copied text'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Add from copied text'), findsOneWidget);
  });
}
