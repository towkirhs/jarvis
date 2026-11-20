import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/arrange.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/item_moves.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the saved tab order: any screen can be a tab, unknown or repeated names are dropped, at most five', () {
    expect(Arrange.tabs(null), ['plan', 'money', 'journal', 'habits']);
    expect(Arrange.tabs('money,plan,money,shop'), ['money', 'plan']);
    expect(Arrange.tabs('day,clock'), ['day', 'clock']);
    expect(Arrange.tabs('plan,money,journal,habits,day,clock'), hasLength(5));
    expect(Arrange.tabs(''), isEmpty);
    expect(Arrange.hidden('ribbon,chips,nope'), {'ribbon', 'chips'});
    expect(Arrange.homeOrder('chips,ribbon'), ['chips', 'ribbon', 'now']);
    final more = Arrange.moreOrder('settings,day', ['plan', 'money']);
    expect(more.take(2), ['settings', 'day']);
    expect(more, isNot(contains('plan')));
    expect(more, contains('journal'));
    expect(Arrange.moreHidden('day,settings,arrange,nope'), {'day'});
  });

  testWidgets('Arrange fits a phone: remove a tab, add Your day as a tab, hide a Home part', (t) async {
    final s = await _store();
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: ArrangePage(store: s)));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Remove the tab').first);
    await t.pumpAndSettle();
    expect(s.local('tabs'), 'money,journal,habits');
    await t.tap(find.text('Add a tab'));
    await t.pumpAndSettle();
    await t.tap(find.text('Your day').last);
    await t.pumpAndSettle();
    expect(s.local('tabs'), 'money,journal,habits,day');
    await t.scrollUntilVisible(find.text('Day strip'), 100, scrollable: find.byType(Scrollable).first);
    await t.tap(find.descendant(of: find.ancestor(of: find.text('Day strip'), matching: find.byType(ListTile)), matching: find.byType(Switch)));
    await t.pumpAndSettle();
    expect(Arrange.hidden(s.local('homeHide')), {'ribbon'});
  });

  testWidgets('More: quick access in your order, groups that open, hidden ones folded, search', (t) async {
    final s = await _store();
    await s.setArrange(tabs: 'plan,day', moreOrder: 'settings', moreHide: 'drive,voice');
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: MoreScreen(store: s))));
    await t.pumpAndSettle();
    expect(find.text('Quick access'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget); // first in your order
    expect(find.text('Your day'), findsNothing); // a tab, so not repeated
    expect(find.text('Money'), findsNothing); // inside a closed group
    await t.tap(find.text('Money and habits'));
    await t.pumpAndSettle();
    expect(find.text('Money'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Hidden (2)'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Google Drive'), findsNothing);
    await t.tap(find.byTooltip('Find a screen'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'drive');
    await t.pumpAndSettle();
    expect(find.text('Google Drive'), findsOneWidget);
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
