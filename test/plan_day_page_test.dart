import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/plan_day_page.dart';
import 'package:jarcis/store.dart';
import 'package:jarcis/task_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _day = DateTime.now().add(const Duration(days: 2));
int _at(int h) => DateTime(_day.year, _day.month, _day.day, h).millisecondsSinceEpoch;

Future<Store> _store(WidgetTester t, {Size size = const Size(420, 1800)}) async {
  Haptics.on = false;
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (_) async => null);
  final s = Store();
  await s.load();
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  return s;
}

Map<String, dynamic> _task(int id, String title, {int? est, bool dated = true}) => {
      'id': id, 'kind': 'task', 'title': title, 'status': 'open', 'est': est, 'priority': 0, 'tags': <String>[], 'list': 'Inbox',
      if (dated) 'when': _at(9),
      if (dated) 'allDay': true,
    };

void main() {
  testWidgets('plans another day: the day can be changed, windows show, and Apply puts tasks on the calendar', (t) async {
    final s = await _store(t);
    s.list('items').add({..._task(1, 'Study for exam', est: 240), 'estMax': 270, 'winFrom': 13 * 60, 'winTo': 20 * 60});
    await t.pumpWidget(MaterialApp(home: PlanDayPage(store: s, day: _day)));
    await t.pumpAndSettle();
    expect(find.text('Study for exam'), findsOneWidget);
    expect(find.textContaining('1:00 pm'), findsOneWidget);
    expect(find.textContaining('has a time window'), findsOneWidget);

    await t.tap(find.byTooltip('Next day'));
    await t.pumpAndSettle();
    expect(find.textContaining('1:00 pm'), findsNothing);
    await t.tap(find.byTooltip('Previous day'));
    await t.pumpAndSettle();

    await t.tap(find.text('Apply plan'));
    await t.pumpAndSettle();
    final it = s.list('items').single;
    expect(DateTime.fromMillisecondsSinceEpoch(it['when'] as int).hour, 13);
    expect(it['allDay'], false);
    expect(it['planned'], dayKey(_day));
    // Nothing left to apply, and the page stays open.
    expect(find.text('Apply plan'), findsNothing);
    expect(find.text('Plan my day'), findsOneWidget);
  });

  testWidgets('tapping a task or a habit in the tray adds it to the day', (t) async {
    final s = await _store(t);
    s.list('items').add(_task(1, 'Write report', est: 60, dated: false));
    s.list('habits').add({'id': 5, 'name': 'Read', 'type': 'yesno', 'start': '2026-01-01', 'sched': {'kind': 'once'}, 'logs': <String, dynamic>{}});
    await t.pumpWidget(MaterialApp(home: PlanDayPage(store: s, day: _day)));
    await t.pumpAndSettle();
    expect(find.textContaining('8:00 am'), findsNothing);

    await t.tap(find.text('Write report'));
    await t.pumpAndSettle();
    expect(find.textContaining('8:00 am – 9:00 am'), findsOneWidget);

    await t.tap(find.text('Habits 1'));
    await t.pumpAndSettle();
    await t.tap(find.text('Read'));
    await t.pumpAndSettle();
    expect(find.textContaining('9:10 am – 9:40 am'), findsOneWidget);
  });

  testWidgets('dragging one piece onto another links them: it comes after, and says so', (t) async {
    final s = await _store(t);
    s.list('items').addAll([{..._task(1, 'Revise', est: 60), 'priority': 3}, _task(2, 'Class notes', est: 60)]);
    await t.pumpWidget(MaterialApp(home: PlanDayPage(store: s, day: _day)));
    await t.pumpAndSettle();
    // Revise is more important, so it is first until it is linked.
    expect(t.getTopLeft(find.text('Revise')).dy, lessThan(t.getTopLeft(find.text('Class notes')).dy));

    final g = await t.startGesture(t.getCenter(find.text('Revise')), kind: PointerDeviceKind.touch);
    await t.pump(const Duration(milliseconds: 700));
    await g.moveTo(t.getCenter(find.text('Class notes')), timeStamp: const Duration(milliseconds: 800));
    await t.pump();
    await g.moveBy(const Offset(4, 4));
    await t.pump();
    await g.up();
    await t.pumpAndSettle();
    await t.tap(find.text('Only if "Class notes" is done'));
    await t.pumpAndSettle();

    expect(s.byId('items', 1)!['needs'], {'any': false, 'if': [{'check': 'done', 'id': 2}]});
    expect(t.getTopLeft(find.text('Class notes')).dy, lessThan(t.getTopLeft(find.text('Revise')).dy));
    expect(find.text('Once Class notes is done'), findsOneWidget);
  });

  testWidgets('a fallback waits on standby, and a task that needs money waits until there is some', (t) async {
    final s = await _store(t);
    s.list('items').addAll([
      _task(1, 'Gym', est: 60),
      {..._task(2, 'Walk', est: 30), 'needs': {'if': [{'check': 'done', 'id': 1, 'not': true}]}},
      {..._task(3, 'Buy shoes', est: 30), 'needs': {'if': [{'check': 'balance', 'account': 'Cash', 'atLeast': 500}]}},
    ]);
    await t.pumpWidget(MaterialApp(home: PlanDayPage(store: s, day: _day)));
    await t.pumpAndSettle();
    expect(find.text('On standby'), findsOneWidget);
    expect(find.text('Only if Gym is not done'), findsOneWidget);
    expect(find.text('Not this day'), findsOneWidget);
    expect(find.textContaining('Cash has at least'), findsOneWidget);

    s.addTx(type: 'income', amount: 800, category: 'Tuition', account: 'Cash');
    await t.pumpAndSettle();
    expect(find.text('Not this day'), findsNothing);
  });

  testWidgets('a task done in blocks becomes parts on Apply, and the last part finishes the task', (t) async {
    final s = await _store(t);
    s.list('items').add({..._task(1, 'Thesis', est: 240), 'chunk': 120});
    await t.pumpWidget(MaterialApp(home: PlanDayPage(store: s, day: _day)));
    await t.pumpAndSettle();
    expect(find.textContaining('block 1 of 2'), findsOneWidget);
    await t.tap(find.text('Apply plan'));
    await t.pumpAndSettle();
    final parts = s.list('items').where((i) => i['partOf'] == 1).toList();
    expect(parts.length, 2);
    await s.markDone(parts[0]);
    expect(s.byId('items', 1)!['status'], 'open');
    await s.markDone(parts[1]);
    expect(s.byId('items', 1)!['status'], 'done');
  });

  testWidgets('on a phone-sized screen nothing overflows: the plan, a piece\'s sheet, and every option of the task form', (t) async {
    final s = await _store(t, size: const Size(360, 720));
    s.list('places').add({'id': 40, 'name': 'Shwapno Dhanmondi', 'lat': 23.7, 'lng': 90.4, 'radius': 200});
    s.list('habits').add({'id': 5, 'name': 'Read twenty pages', 'type': 'yesno', 'planMin': 30, 'start': '2026-01-01', 'sched': {'kind': 'daily'}, 'logs': <String, dynamic>{}});
    s.list('items').addAll([
      {..._task(1, 'A long task name that will need two lines to show fully', est: 240), 'chunk': 120, 'winFrom': 600, 'winTo': 1200},
      {..._task(2, 'Buy shoes', est: 30), 'needs': {'any': true, 'if': [{'check': 'balance', 'account': 'Cash', 'atLeast': 500}, {'check': 'done', 'id': 1}]},
        'place': 40, 'placeWhen': 'arrive', 'location': 'Shwapno Dhanmondi', 'priority': 3, 'color': 'rose', 'tags': ['errand']},
      _task(3, 'Call the landlord about the water'),
      for (var k = 10; k < 16; k++) _task(k, 'Extra task number $k', est: 45, dated: false),
    ]);
    await t.pumpWidget(MaterialApp(home: PlanDayPage(store: s, day: _day)));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(find.text('Buy shoes'));
    await t.pumpAndSettle();
    expect(find.text('Only if'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(find.text('All options'), warnIfMissed: false);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Counts as done when'), 200, scrollable: find.byType(Scrollable).last);
    expect(t.takeException(), isNull);
  });

  testWidgets('the task form on a phone-sized screen: only a name is needed, the rest is under More options', (t) async {
    final s = await _store(t, size: const Size(360, 720));
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => showTaskSheet(c, s), child: const Text('open'))))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Does it take time?'), findsOneWidget);
    expect(find.text('Location'), findsNothing);
    await t.enterText(find.byType(TextField).first, 'Buy milk');
    await t.tap(find.text('More options'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Counts as done when'), 200, scrollable: find.byType(Scrollable).first);
    expect(t.takeException(), isNull);
    await t.tap(find.text('Add'));
    await t.pumpAndSettle();
    expect(s.list('items').single['title'], 'Buy milk');
  });
}
