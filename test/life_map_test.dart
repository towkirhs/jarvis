import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/areas.dart';
import 'package:jarcis/brain.dart';
import 'package:jarcis/day_log.dart';
import 'package:jarcis/day_planner.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/life_map_page.dart';
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

final _areas = <Rec>[
  {'id': 1, 'name': 'Health', 'words': ['gym', 'walk'], 'x': 0.45, 'y': 0.5}, // near the middle
  {'id': 2, 'name': 'Jarvis', 'words': ['code', 'vs code'], 'x': 0.7, 'y': 0.45}, // side, work
  {'id': 3, 'name': 'Friends', 'words': ['friends'], 'x': 0.08, 'y': 0.5}, // edge
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('where an area sits says its focus, zone and side', () {
    expect([Areas.focus(_areas[0]), Areas.zone(_areas[0]), Areas.isWork(_areas[0])], [91, 'focus', false]);
    expect([Areas.zone(_areas[1]), Areas.isWork(_areas[1])], ['side', true]);
    expect([Areas.zone(_areas[2]), Areas.focus(_areas[2]) < 30], ['maintenance', true]);
    final p = Areas.place(_areas[2], 'focus');
    expect(Areas.zone({'x': p.x, 'y': p.y}), 'focus');
    final w = Areas.place(_areas[2], 'side', work: true);
    expect([Areas.zone({'x': w.x, 'y': w.y}), w.x > 0.5], ['side', true]);
  });

  test('a record finds its area by its own choice first, then by words', () {
    expect(Areas.of(_areas, {'title': 'Gym at 6'})?['name'], 'Health');
    expect(Areas.of(_areas, {'name': 'Morning walks'})?['name'], 'Health');
    expect(Areas.of(_areas, {'title': 'Write code for the bubble'})?['name'], 'Jarvis');
    expect(Areas.of(_areas, {'title': 'Gym', 'area': 3})?['name'], 'Friends');
    expect(Areas.of(_areas, {'title': 'Buy milk'}), isNull);
    expect(Areas.ofText(_areas, 'VS Code'), same(_areas[1]));
  });

  test('time by area comes from Your day, app time and finished tasks; sleep is left out', () {
    final day = DateTime(2026, 11, 20);
    int at(int h, [int m = 0]) => DateTime(2026, 11, 20, h, m).millisecondsSinceEpoch;
    final log = <Rec>[
      {'id': 1, 'at': at(7), 'kind': 'now', 'verb': 'start', 'text': 'Started gym'},
      {'id': 2, 'at': at(8), 'kind': 'now', 'verb': 'back', 'text': 'Back home'},
      {'id': 3, 'at': at(23), 'kind': 'now', 'verb': 'sleep', 'text': 'Going to sleep'},
    ];
    final items = <Rec>[
      {'id': 9, 'kind': 'task', 'title': 'Call friends', 'status': 'done', 'doneAt': at(20), 'actual': 30},
    ];
    final apps = [AppSession('code.vs', 'VS Code', DateTime(2026, 11, 20, 14), DateTime(2026, 11, 20, 16))];
    final m = Areas.minutes(_areas, log: log, items: items, from: day, to: day.add(const Duration(days: 1)), now: DateTime(2026, 11, 21), apps: apps);
    expect([m[1], m[2], m[3]], [60, 120, 30]);
    expect(m[0], greaterThan(0)); // "Back home" until sleep has no area
  });

  test('the week shows what does not line up', () {
    final notes = Areas.notes(_areas, {1: 30, 2: 600, 3: 0}, {1: 30, 2: 900, 3: 0});
    expect(notes, [
      'Health is in your centre but got 30m this week.',
      'Friends got no time for 3 weeks. Keep it where it is?',
    ]);
    expect(Areas.forAi(_areas, {1: 30}), contains('- Health: life, Main focus (focus 91), 30m this week'));
  });

  test('Plan my day places the centre area first when nothing else decides', () {
    final now = DateTime(2026, 11, 20, 9);
    final items = <Rec>[
      {'id': 1, 'kind': 'task', 'title': 'Message friends', 'status': 'open', 'est': 60},
      {'id': 2, 'kind': 'task', 'title': 'Gym', 'status': 'open', 'est': 60},
    ];
    final focus = Areas.focusOf(_areas, items);
    expect(focus, {1: Areas.focus(_areas[2]), 2: 91});
    final plan = DayPlanner.plan(now: now, items: items, focus: focus);
    final first = plan.blocks.where((b) => !b.fixed).first;
    expect(first.title, 'Gym');
  });

  test('the chat can add and move an area, and a task gets the area it names', () async {
    final s = await _store();
    await Brain.capture(s, 'JARVIS v1 {"reply":"Done.","items":[{"type":"area","title":"Friends","zone":"focus","side":"life","status":"bad","words":["hangout"]}]}');
    final a = s.list('areas').single;
    expect([Areas.zone(a), Areas.isWork(a), a['status'], a['words']], ['focus', false, 'bad', ['hangout']]);
    await Brain.capture(s, 'JARVIS v1 {"reply":"Moved.","items":[{"type":"area","title":"friends","zone":"maintenance"}]}');
    expect([s.list('areas').length, Areas.zone(s.list('areas').single)], [1, 'maintenance']);
    await Brain.capture(s, 'JARVIS v1 {"reply":"Added.","items":[{"type":"task","title":"Plan the weekend trip","area":"Friends"}]}');
    expect(s.list('items').single['area'], a['id']);
    expect(Brain.world(s), contains('Life map'));
  });

  testWidgets('Life map: start with the usual areas, drag one to the middle', (t) async {
    final s = await _store();
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: LifeMapPage(store: s)));
    await t.pumpAndSettle();
    await t.tap(find.text('Start with the usual ones'));
    await t.pumpAndSettle();
    expect(s.list('areas'), hasLength(Areas.starters().length));
    final friends = s.list('areas').firstWhere((a) => a['name'] == 'Friends');
    expect(Areas.zone(friends), isNot('focus'));
    final from = t.getCenter(find.text('Friends'));
    final mid = t.getCenter(find.ancestor(of: find.text('Life'), matching: find.byType(Stack)).first);
    await t.dragFrom(from, mid - from);
    await t.pumpAndSettle();
    expect(Areas.zone(s.byId('areas', friends['id'] as int)!), 'focus');
    expect(find.textContaining('Plan my day places its tasks first'), findsOneWidget);
    await t.tap(find.text('Friends'));
    await t.pumpAndSettle();
    expect(find.text('Words that mean this area'), findsOneWidget);
  });
}
