import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/day_log.dart';
import 'package:jarcis/habit_core.dart';
import 'package:jarcis/habit_link.dart';
import 'package:jarcis/habits_screen.dart';
import 'package:jarcis/haptics.dart';
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
  final now = DateTime(2026, 11, 19, 21);
  int ms(int h, [int m = 0]) => DateTime(2026, 11, 19, h, m).millisecondsSinceEpoch;

  test('a finished Your day stretch logs the habit with its name, with its minutes', () {
    final h = {'id': 1, 'name': 'Tuition', 'type': 'duration', 'logs': <String, dynamic>{}};
    final yes = {'id': 2, 'name': 'Gym', 'type': 'yesno', 'link': ['workout'], 'logs': <String, dynamic>{}};
    final did = [(title: 'Tuition', start: ms(17), end: ms(18, 30)), (title: 'Morning workout', start: ms(7), end: ms(8))];
    expect(HabitLink.compute(h, const [], now, did: did), {'2026-11-19': {'v': 90, 'cal': true}});
    expect(HabitLink.compute(yes, const [], now, did: did), {'2026-11-19': {'v': 1, 'cal': true}});
  });

  test('usual time: the middle of the last times, once there are three', () {
    expect(HabitCore.usualTime({'doneTimes': ['07:10', '07:40']}), isNull);
    expect(HabitCore.usualTime({'doneTimes': ['07:10', '09:00', '07:40', '07:20']}), '07:40');
    expect(HabitCore.remindAt({'remind': 'auto'}), '20:00');
    expect(HabitCore.remindAt({'remind': '06:30'}), '06:30');
  });

  test('an app habit takes the minutes in that app, unless you logged the day yourself', () async {
    final s = await _store();
    final h = {'id': 9, 'name': 'Less Facebook', 'type': 'limit', 'target': 60, 'app': {'pkg': 'fb', 'name': 'Facebook'}, 'logs': <String, dynamic>{}};
    s.list('habits').add(h);
    final sessions = [
      AppSession('fb', 'Facebook', DateTime(2026, 11, 19, 8), DateTime(2026, 11, 19, 8, 20)),
      AppSession('fb', 'Facebook', DateTime(2026, 11, 19, 12), DateTime(2026, 11, 19, 12, 25)),
      AppSession('yt', 'YouTube', DateTime(2026, 11, 19, 13), DateTime(2026, 11, 19, 14)),
    ];
    expect(s.applyAppTime(sessions, '2026-11-19'), isTrue);
    expect((h['logs'] as Map)['2026-11-19'], {'v': 45, 'app': true});
    expect(s.applyAppTime(sessions, '2026-11-19'), isFalse);
    (h['logs'] as Map)['2026-11-19'] = {'v': 10};
    expect(s.applyAppTime(sessions, '2026-11-19'), isFalse);
  });

  testWidgets('a routine goes one habit at a time and logs them', (t) async {
    final s = await _store();
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final a = await s.addHabit('Stretch', 7);
    final b = await s.addHabit('Read', 7);
    await t.pumpWidget(MaterialApp(home: RoutinePage(store: s, name: 'Morning routine', ids: [a['id'] as int, b['id'] as int])));
    await t.pumpAndSettle();
    expect(find.text('Stretch'), findsOneWidget);
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(find.text('Read'), findsOneWidget);
    await t.tap(find.text('Skip for now'));
    await t.pumpAndSettle();
    expect(find.text('Morning routine done'), findsOneWidget);
    expect((a['logs'] as Map).values.single, 'yes');
    expect((b['logs'] as Map), isEmpty);
  });
}
