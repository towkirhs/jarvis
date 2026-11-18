import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/cal_grid.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The grid starts on this Monday; every test uses a 3-day page so each column is 284 px wide.
final _day = DateTime(2026, 11, 16);

Future<Store> _store(List<Map<String, dynamic>> items) async {
  SharedPreferences.setMockInitialValues({});
  final s = Store();
  await s.load();
  s.list('items').addAll(items);
  return s;
}

Map<String, dynamic> _ev(int id, String title, int hour, {int dur = 60, String? repeat}) => {
      'id': id, 'kind': 'event', 'title': title, 'status': 'open', 'allDay': false,
      'when': DateTime(2026, 11, 16, hour).millisecondsSinceEpoch,
      'dur': dur, 'repeat': repeat, 'priority': 0, 'tags': <String>[], 'list': 'Inbox', 'lead': 0,
    };

Future<List<DateTime>> _pump(WidgetTester t, Store s) async {
  Haptics.on = false;
  t.view.physicalSize = const Size(900, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (_) async => null);
  final seen = <DateTime>[];
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: TimeGrid(store: s, anchor: _day, count: 3, onVisible: seen.add, onDayTap: (_) {}),
    ),
  ));
  await t.pumpAndSettle();
  return seen;
}

void main() {
  testWidgets('a daily repeat shows once in each of the three days', (t) async {
    final s = await _store([_ev(1, 'Standup', 9, repeat: 'daily')]);
    await _pump(t, s);
    expect(find.text('Standup'), findsNWidgets(3));
  });

  testWidgets('swiping moves the grid to the next three days', (t) async {
    final s = await _store([_ev(1, 'Physics', 9)]);
    final seen = await _pump(t, s);
    expect(find.text('Physics'), findsOneWidget);
    await t.fling(find.byType(PageView).last, const Offset(-600, 0), 1500);
    await t.pumpAndSettle();
    expect(seen.last, DateTime(2026, 11, 19));
    expect(find.text('Physics'), findsNothing);
  });

  testWidgets('tapping an empty slot opens quick add, and Save adds the event', (t) async {
    final s = await _store([]);
    await _pump(t, s);
    // column 2 (middle), about 14:00; the hour lines start at the top of the scrolled body
    await t.tapAt(const Offset(48 + 284 * 1.5, 0) + Offset(0, _bodyTop(t) + 14 * 60.0 + 10));
    await t.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Add title'), 'Lunch');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final added = s.list('items').where((i) => i['title'] == 'Lunch').toList();
    expect(added.length, 1);
    final when = DateTime.fromMillisecondsSinceEpoch(added.first['when'] as int);
    expect(when.day, 17);
    expect(when.hour, 14);
  });

  testWidgets('long-press and drag moves an event two hours later', (t) async {
    final s = await _store([_ev(1, 'Physics', 9)]);
    await _pump(t, s);
    final g = await t.startGesture(t.getCenter(find.text('Physics')), kind: PointerDeviceKind.touch);
    await t.pump(const Duration(milliseconds: 700));
    await g.moveBy(const Offset(0, 120));
    await t.pump();
    await g.up();
    await t.pumpAndSettle();
    final when = DateTime.fromMillisecondsSinceEpoch(s.list('items').first['when'] as int);
    expect(when.hour, 11);
    expect(when.minute, 0);
    expect(find.text('Undo'), findsOneWidget);
    // The Undo pop-up goes away by itself.
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('with Overlap on, an event at the same time lies over the first one instead of beside it', (t) async {
    final s = await _store([_ev(1, 'Walk', 9, dur: 120), _ev(2, 'Call', 9)]);
    Haptics.on = false;
    t.view.physicalSize = const Size(900, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Future<Size> callSize(bool stack) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: TimeGrid(key: ValueKey(stack), store: s, anchor: _day, count: 3, stack: stack, onVisible: (_) {}, onDayTap: (_) {})),
      ));
      await t.pumpAndSettle();
      return t.getSize(find.ancestor(of: find.text('Call'), matching: find.byType(Opacity)).first);
    }

    final beside = await callSize(false);
    final over = await callSize(true);
    expect(beside.width, closeTo(284 / 2 - 2, 1));
    expect(over.width, closeTo(284 * 0.78 - 2, 1));
  });

  testWidgets('dragging the bottom handle makes the event longer, in quarter hours', (t) async {
    final s = await _store([_ev(1, 'Physics', 9)]);
    await _pump(t, s);
    final box = t.getRect(find.text('Physics'));
    final handle = Offset(box.center.dx, box.top - 2 + 60 - 6);
    await t.dragFrom(handle, const Offset(0, 90));
    await t.pumpAndSettle();
    final dur = s.list('items').first['dur'] as int;
    expect(dur, greaterThan(60));
    expect(dur % 15, 0);
  });

  testWidgets('with the day starting at 5 am, 1:30 am sits at the bottom of the day before', (t) async {
    final s = await _store([
      {..._ev(1, 'Late study', 0), 'when': DateTime(2026, 11, 17, 1, 30).millisecondsSinceEpoch},
    ]);
    await s.setDayShift(true);
    await _pump(t, s);
    final box = t.getRect(find.text('Late study'));
    expect(box.left, lessThan(48 + 284.0 * 1 + 10)); // the first column: Monday the 16th
    expect(find.text('6 am'), findsOneWidget); // hour labels start at 5 am
    expect(find.text('2 am'), findsOneWidget);

    await s.setDayShift(false);
    await t.pumpWidget(const SizedBox());
    await _pump(t, s);
    expect(t.getRect(find.text('Late study')).left, greaterThan(48 + 284.0)); // back on Tuesday the 17th
  });

  testWidgets('Plan and what you did: plan on the left half, what you did on the right; tap the right to add', (t) async {
    final s = await _store([_ev(1, 'Class', 9)]);
    s.list('log').add({
      'id': 5, 'kind': 'now', 'verb': 'start', 'text': 'Started tuition',
      'at': DateTime(2026, 11, 16, 10).millisecondsSinceEpoch, 'end': DateTime(2026, 11, 16, 11, 30).millisecondsSinceEpoch,
    });
    Haptics.on = false;
    t.view.physicalSize = const Size(900, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (_) async => null);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: TimeGrid(store: s, anchor: _day, count: 3, done: true, onVisible: (_) {}, onDayTap: (_) {})),
    ));
    await t.pumpAndSettle();
    final plan = t.getRect(find.ancestor(of: find.text('Class'), matching: find.byType(Opacity)).first);
    final did = t.getRect(find.byKey(ValueKey('done5@${DateTime(2026, 11, 16, 10).millisecondsSinceEpoch}')));
    expect(plan.width, closeTo(284 / 2 - 2, 1));
    expect(did.left - plan.left, closeTo(142, 1));
    expect(did.height, closeTo(GridMath.hourH * 1.5 - 1, 1));

    // An empty slot on the right side of Tuesday at 8 am.
    await t.tapAt(Offset(48 + 284 + 200, _bodyTop(t) + 8 * GridMath.hourH + 5));
    await t.pumpAndSettle();
    expect(find.text('Add what you did'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Reading');
    await t.tap(find.text('Add'));
    await t.pumpAndSettle();
    final added = s.list('log').last;
    expect([added['text'], DateTime.fromMillisecondsSinceEpoch(added['at'] as int)], ['Started Reading', DateTime(2026, 11, 17, 8)]);
  });
}

/// Where the hour grid begins on screen (below the names row). The tall test window never scrolls it.
double _bodyTop(WidgetTester t) => t.getTopLeft(find.byType(SingleChildScrollView).first).dy;
