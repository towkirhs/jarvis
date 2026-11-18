import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/arrange.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/item_moves.dart';
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

  test('the saved tab order: unknown or repeated names are dropped, nothing saved means all four', () {
    expect(Arrange.tabs(null), ['plan', 'money', 'journal', 'habits']);
    expect(Arrange.tabs('money,plan,money,shop'), ['money', 'plan']);
    expect(Arrange.tabs(''), isEmpty);
    expect(Arrange.hidden('ribbon,chips,nope'), {'ribbon', 'chips'});
  });

  testWidgets('Arrange screens fits a phone; hiding a tab and a Home part is saved', (t) async {
    final s = await _store();
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: ArrangePage(store: s)));
    await t.pumpAndSettle();
    // The first switch belongs to Plan.
    await t.tap(find.byType(Switch).first);
    await t.pumpAndSettle();
    expect(s.local('tabs'), 'money,journal,habits');
    await t.scrollUntilVisible(find.text('Day strip'), 100, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Day strip'));
    await t.pumpAndSettle();
    expect(Arrange.hidden(s.local('homeHide')), {'ribbon'});
  });

  test('a task moves to another day keeping its time, gets copied, and turns into a habit with Undo', () async {
    final s = await _store();
    final undo = <Rec>[];
    final it = await s.addItem(kind: 'task', title: 'Read', when: DateTime(2030, 1, 5, 20, 30).millisecondsSinceEpoch, undo: undo);
    await ItemMoves.moveTo(s, it, DateTime(2030, 1, 9));
    expect(fromMs(it['when'] as int), DateTime(2030, 1, 9, 20, 30));

    final copy = await ItemMoves.duplicate(s, it);
    expect([copy['title'], copy['status'], copy['id'] != it['id']], ['Read', 'open', true]);
    expect(ItemMoves.asText(it), startsWith('Read\n'));

    final h = await ItemMoves.toHabit(s, it);
    expect([h['name'], h['times'], h['remind'], it['status']], ['Read', 7, '20:30', 'cancelled']);
    await s.undo(s.list('actions').last['id'] as int);
    expect(s.byId('items', it['id'] as int)!['status'], 'open');
    expect(s.list('habits'), isEmpty);
  });
}
