import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/brain.dart';
import 'package:jarcis/day_planner.dart';
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
  tearDown(() => DayStart.minutes = 0);

  List<Map<String, dynamic>> tasks() => [
        for (var i = 1; i <= 3; i++) {'id': i, 'kind': 'task', 'title': 'Work $i', 'status': 'open', 'est': 110},
      ];

  test('Plan my day runs past midnight to your bedtime, the same day', () {
    final now = DateTime(2026, 11, 20, 21);
    final plan = DayPlanner.plan(now: now, items: tasks(), dayShift: 300, dayStartMinute: 300, dayEndMinute: 1620, buffer: 0);
    final placed = plan.blocks.where((b) => !b.fixed).toList();
    expect(placed, hasLength(3));
    expect(placed.last.start.isAfter(DateTime(2026, 11, 21)), isTrue); // after midnight
    expect(placed.last.end.isAfter(DateTime(2026, 11, 21, 3)), isFalse); // not past 3 am
    // With the old 10 pm end nothing fits tonight.
    final old = DayPlanner.plan(now: now, items: tasks(), dayShift: 300, buffer: 0);
    expect(old.blocks.where((b) => !b.fixed), isEmpty);
  });

  test('at 1 am the plan is still the same day and goes on until bedtime', () {
    final now = DateTime(2026, 11, 21, 1);
    final plan = DayPlanner.plan(now: now, items: tasks().take(1).toList(), dayShift: 300, dayStartMinute: 300, dayEndMinute: 1620, buffer: 0);
    final b = plan.blocks.where((b) => !b.fixed).single;
    expect([b.start.day, b.start.hour], [21, 1]);
  });

  test('sleeping after midnight turns on the 5 am day and keeps the night in the day', () async {
    final s = await _store();
    expect([s.wakeMin, s.sleepMin], [480, 1320]);
    await s.setMyDay(wake: 300, sleep: 180);
    expect([s.dayShift, s.wakeMin, s.sleepMin], [300, 300, 1620]);
    await s.setMyDay(wake: 600, sleep: 360); // 6 am would be the next day: 4:59 am
    expect(s.sleepMin, 1440 + 299);
  });

  test('"today at 1 am" is tonight, not the night before', () {
    DayStart.minutes = 300;
    final d = DateTime.parse(DayStart.today());
    final ms = Brain.whenFrom(DayStart.today(), '01:00')!;
    expect(DateTime.fromMillisecondsSinceEpoch(ms), DateTime(d.year, d.month, d.day + 1, 1));
    // An evening time on that day is unchanged.
    expect(DateTime.fromMillisecondsSinceEpoch(Brain.whenFrom(DayStart.today(), '20:00')!), DateTime(d.year, d.month, d.day, 20));
  });
}
