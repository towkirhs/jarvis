import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/items_screen.dart';
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

  test('usual lengths come from finished tasks and Your day', () async {
    final s = await _store();
    final now = DateTime.now();
    int ago(int h) => now.subtract(Duration(hours: h)).millisecondsSinceEpoch;
    s.list('items').addAll([
      {'id': 1, 'kind': 'task', 'status': 'done', 'title': 'Laundry', 'actual': 40},
      {'id': 2, 'kind': 'task', 'status': 'done', 'title': 'laundry', 'actual': 50},
    ]);
    s.list('log').addAll([
      {'id': 3, 'kind': 'now', 'verb': 'start', 'text': 'Started laundry', 'at': ago(30), 'end': ago(29)},
      {'id': 4, 'kind': 'now', 'verb': 'start', 'text': 'Started Tuition', 'at': ago(5), 'end': ago(3)},
    ]);
    final m = s.usualMinutes();
    expect(m['laundry'], 50);
    expect(m['tuition'], 120);
  });

  testWidgets('one Plan screen: List, Calendar, Plan, Day log and Matrix', (t) async {
    final s = await _store();
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: ItemsScreen(store: s)));
    await t.pumpAndSettle();
    await t.tap(find.text('Plan'));
    await t.pumpAndSettle();
    expect(find.textContaining('Top 3'), findsOneWidget);
    await t.tap(find.text('Day log'));
    await t.pumpAndSettle();
    expect(find.text('Your day'), findsWidgets);
    await t.tap(find.text('Matrix'));
    await t.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
