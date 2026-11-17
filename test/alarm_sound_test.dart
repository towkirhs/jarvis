import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/alarm_sound.dart';
import 'package:jarcis/clock_screen.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('intensity reads plainly', () {
    expect(AlarmStyle.describe(null), 'Your usual');
    expect(AlarmStyle.describe({'vol': 60, 'rise': true, 'vib': false}), 'Loudness 60% · gets louder slowly · no vibration');
    expect(AlarmStyle.describe({'vol': 100, 'rise': false, 'vib': true}), 'Loudness 100% · vibrates');
  });

  test('both alarm sounds come with the app', () async {
    for (final b in AlarmSounds.builtIn) {
      expect((await rootBundle.load(b.asset)).lengthInBytes, greaterThan(100000));
    }
  });

  testWidgets('an alarm\'s intensity can be set on a phone screen and is saved with it', (t) async {
    Haptics.on = false;
    SharedPreferences.setMockInitialValues({});
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (call) async {
      calls.add(call);
      return null;
    });
    final s = Store();
    await s.load();
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(body: Center(child: TextButton(onPressed: () => showAlarmEditor(context, s), child: const Text('Open'))))),
    ));
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Intensity'));
    await t.tap(find.text('Change'));
    await t.pumpAndSettle();
    await t.tap(find.text('Get louder slowly'));
    await t.pumpAndSettle();
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(find.text('Loudness 100% · gets louder slowly · vibrates'), findsOneWidget);
    await t.ensureVisible(find.text('Add'));
    await t.tap(find.text('Add'));
    await t.pumpAndSettle();
    expect(s.list('clocks').single['style'], {'vol': 100, 'rise': true, 'vib': true});
    final clock = calls.lastWhere((c) => c.method == 'clock');
    expect((clock.arguments as Map)['style'], contains('"rise":true'));
  });
}
