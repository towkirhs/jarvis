import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/brain.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/home_screen.dart';
import 'package:jarcis/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Store> _store({String? heard}) async {
  Haptics.on = false;
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (call) async => call.method == 'hear' ? heard : null);
  final s = Store();
  await s.load();
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a ChatGPT profile item adds a file, and the same name replaces it', () async {
    final s = await _store();
    final undo = <Map<String, dynamic>>[];
    await Brain.applyParsed(s, {'type': 'profile', 'title': 'Routines', 'keys': ['gym'], 'text': 'Gym at 6.'}, 1, const [], undo);
    await Brain.applyParsed(s, {'type': 'profile', 'title': 'routines', 'keys': ['gym'], 'text': 'Gym at 7.'}, 1, const [], undo);
    expect(s.list('profile').single['text'], 'Gym at 7.');
  });

  testWidgets('the mic puts what was heard in the box, with your words fixed, and does not send it', (t) async {
    final s = await _store(heard: 'buy dua ris cream');
    s.list('words').add({'id': 1, 'from': 'dua ris', 'to': 'Duaris'});
    t.view.physicalSize = const Size(900, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: HomeScreen(store: s))));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.byTooltip('Speak'));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('buy Duaris cream'), findsOneWidget);
    expect(s.list('captures'), isEmpty);
  });
}
