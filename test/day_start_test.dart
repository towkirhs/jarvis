import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/brain.dart';
import 'package:jarcis/day_log.dart';
import 'package:jarcis/day_start_menu.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/money_stats.dart';
import 'package:jarcis/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

int _ms(int y, int m, int d, int h, [int mi = 0]) => DateTime(y, m, d, h, mi).millisecondsSinceEpoch;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => DayStart.minutes = 0);

  test('with the day starting at 5 am, 1 am belongs to yesterday; all-day items keep their date', () {
    expect(DayStart.key(_ms(2026, 11, 18, 1)), '2026-11-18');
    DayStart.minutes = 300;
    expect(DayStart.key(_ms(2026, 11, 18, 1)), '2026-11-17');
    expect(DayStart.key(_ms(2026, 11, 18, 5)), '2026-11-18');
    expect(DayStart.itemDay({'when': _ms(2026, 11, 18, 0), 'allDay': true}), '2026-11-18');
    expect(DayStart.itemDay({'when': _ms(2026, 11, 18, 2), 'allDay': false}), '2026-11-17');
  });

  test('money: a 1 am spend on the 1st counts in the month before', () {
    DayStart.minutes = 300;
    final tx = [
      {'type': 'expense', 'amount': 100, 'ts': _ms(2026, 12, 1, 1)},
      {'type': 'expense', 'amount': 50, 'ts': _ms(2026, 12, 1, 9)},
    ];
    final m = MoneyStats.months(tx, DateTime(2026, 12), months: 2);
    expect([for (final x in m) x.expense], [100, 50]);
  });

  test('Your day: what you said at 2 am is on the day before', () {
    DayStart.minutes = 300;
    final log = [
      {'id': 1, 'at': _ms(2026, 11, 18, 2), 'kind': 'now', 'verb': 'start', 'text': 'Started reading'},
    ];
    expect(DayLog.timeline(DateTime(2026, 11, 17), log: log, items: const []).single.text, 'Started reading');
    expect(DayLog.timeline(DateTime(2026, 11, 18), log: log, items: const []), isEmpty);
  });

  test('the AI is told the day is still yesterday before 5 am', () {
    DayStart.minutes = 300;
    final note = Brain.dayStartNote(DateTime(2026, 11, 18, 1, 30));
    expect(note, contains('still Tuesday 2026-11-17'));
    expect(note, contains('"tomorrow" means 2026-11-18'));
    expect(Brain.dayStartNote(DateTime(2026, 11, 18, 9)), isEmpty);
    DayStart.minutes = 0;
    expect(Brain.dayStartNote(DateTime(2026, 11, 18, 1, 30)), isEmpty);
  });

  testWidgets('the switch in Settings and the section menus is one setting, kept after a restart', (t) async {
    Haptics.on = false;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (call) async => null);
    final s = Store();
    await s.load();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(appBar: AppBar(actions: [DayStartMenu(store: s)]), body: DayStartSwitch(store: s)),
    ));
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect([s.dayShift, DayStart.minutes], [300, 300]);

    await t.tap(find.byTooltip('Options'));
    await t.pumpAndSettle();
    await t.tap(find.byType(CheckedPopupMenuItem<String>));
    await t.pumpAndSettle();
    expect([s.dayShift, DayStart.minutes], [0, 0]);

    await s.setDayShift(true);
    DayStart.minutes = 0;
    await Store().load();
    expect(DayStart.minutes, 300);
  });
}
