import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/plan_day_page.dart';
import 'package:jarcis/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('plans another day: the day can be changed, windows show, and Apply puts tasks on the calendar', (t) async {
    Haptics.on = false;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (_) async => null);
    final s = Store();
    await s.load();
    final day = DateTime.now().add(const Duration(days: 2));
    s.list('items').add({
      'id': 1, 'kind': 'task', 'title': 'Study for exam', 'status': 'open', 'est': 240, 'estMax': 270,
      'winFrom': 13 * 60, 'winTo': 20 * 60, 'priority': 0, 'tags': <String>[], 'list': 'Inbox',
      'when': DateTime(day.year, day.month, day.day, 9).millisecondsSinceEpoch, 'allDay': true,
    });
    t.view.physicalSize = const Size(900, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: PlanDayPage(store: s, day: day)));
    await t.pumpAndSettle();
    expect(find.text('Study for exam'), findsOneWidget);
    expect(find.textContaining('1:00 pm'), findsOneWidget);
    expect(find.textContaining('has a time window'), findsOneWidget);
    expect(find.text('Add tasks'), findsOneWidget);

    await t.tap(find.byTooltip('Next day'));
    await t.pumpAndSettle();
    expect(find.text('Study for exam'), findsNothing);
    await t.tap(find.byTooltip('Previous day'));
    await t.pumpAndSettle();

    await t.tap(find.text('Apply this plan'));
    await t.pumpAndSettle();
    final it = s.list('items').single;
    final when = DateTime.fromMillisecondsSinceEpoch(it['when'] as int);
    expect(when.hour, 13);
    expect(it['allDay'], false);
    expect(it['planned'], dayKey(day));
  });
}
