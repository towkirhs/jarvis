import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/cal_grid.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/items_screen.dart';
import 'package:jarcis/main_nav.dart';
import 'package:jarcis/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Store> _open(WidgetTester t) async {
  Haptics.on = false;
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (_) async => null);
  final s = Store();
  await s.load();
  final now = DateTime.now();
  s.list('items').add({
    'id': 1, 'kind': 'event', 'title': 'Physics class', 'status': 'open', 'allDay': false, 'dur': 60, 'priority': 0,
    'tags': <String>[], 'list': 'Inbox', 'lead': 0, 'when': DateTime(now.year, now.month, now.day, 10).millisecondsSinceEpoch,
  });
  t.view.physicalSize = const Size(360, 720);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: ItemsScreen(store: s)));
  await t.pumpAndSettle();
  return s;
}

void main() {
  testWidgets('the Today button offers every span, both layouts, and saves your default', (t) async {
    final s = await _open(t);
    await t.tap(find.text('Calendar'));
    await t.pumpAndSettle();
    expect(find.byType(TimeGrid), findsOneWidget);

    await t.tap(find.text('Today'));
    await t.pumpAndSettle();
    for (final span in ['1 day', '2 days', '3 days', 'Week', '15 days', '30 days', 'Month']) {
      expect(find.text(span), findsOneWidget);
    }
    await t.tap(find.text('15 days'));
    await t.pumpAndSettle();
    await t.tap(find.text('Hours across'));
    await t.pumpAndSettle();
    await t.tap(find.text('Use this as my default'));
    await t.pumpAndSettle();
    expect(s.local('calView'), '15|1|0');
    expect(find.byType(TimelineGrid), findsOneWidget);
    expect(find.byType(TimeGrid), findsNothing);

    // Every other span and layout lays out on a phone without spilling.
    for (final span in ['1 day', '2 days', '3 days', 'Week', '30 days', 'Month']) {
      await t.tap(find.text('Today'));
      await t.pumpAndSettle();
      await t.tap(find.text(span));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(180, 40)); // close the sheet
      await t.pumpAndSettle();
    }
    await t.tap(find.text('Today'));
    await t.pumpAndSettle();
    await t.tap(find.text('30 days'));
    await t.pumpAndSettle();
    await t.tap(find.text('Hours across'));
    await t.pumpAndSettle();
  });

  testWidgets('swiping moves between List, Calendar and Matrix, and past the first one on to the main tabs', (t) async {
    await _open(t);
    final steps = <int>[];
    MainNav.step = steps.add;
    addTearDown(() => MainNav.step = null);

    await t.fling(find.byType(TabBarView), const Offset(300, 0), 1200); // right, on the first tab
    await t.pumpAndSettle();
    expect(steps, [-1]);

    await t.fling(find.byType(TabBarView), const Offset(-300, 0), 1200);
    await t.pumpAndSettle();
    expect(find.byType(TimeGrid), findsOneWidget);
  });

  testWidgets('quick add on a phone: the sheet lays out and saves', (t) async {
    final s = await _open(t);
    await t.tap(find.text('Calendar'));
    await t.pumpAndSettle();
    await t.tap(find.byType(FloatingActionButton));
    await t.pumpAndSettle();
    expect(find.text('Starts'), findsOneWidget);
    expect(find.text('Ends'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Add title'), 'Dentist');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(s.list('items').any((i) => i['title'] == 'Dentist'), true);
  });
}
