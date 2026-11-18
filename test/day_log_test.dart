import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/app_alarms.dart';
import 'package:jarcis/brain.dart';
import 'package:jarcis/day_log.dart';
import 'package:jarcis/day_page.dart';
import 'package:jarcis/destination.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _today = DateTime.now();
DateTime _at(int h, [int m = 0]) => DateTime(_today.year, _today.month, _today.day, h, m);
int _ms(int h, [int m = 0]) => _at(h, m).millisecondsSinceEpoch;

/// A phone with usage access whose app history is [sessions].
Future<Store> _store({List<Map<String, Object>> sessions = const []}) async {
  Haptics.on = false;
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (call) async => switch (call.method) {
            'usageAccess' => true,
            'appSessions' => sessions,
            'apps' => [
                {'pkg': 'com.google.android.youtube', 'name': 'YouTube'},
                {'pkg': 'com.whatsapp', 'name': 'WhatsApp'},
              ],
            _ => null,
          });
  final s = Store();
  await s.load();
  return s;
}

Map<String, dynamic> _planned(int id, String title, int h, int est, {String status = 'open'}) => {
      'id': id, 'kind': 'task', 'title': title, 'status': status, 'est': est, 'priority': 0, 'tags': <String>[],
      'list': 'Inbox', 'when': _ms(h), 'allDay': false, 'planned': dayKey(_today), 'nid': 500 + id,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('"started gym", "back home", "woke up" are logs; a note with a time is a plan', () {
    expect(NowLog.parse('started gym')!.text, 'Started gym');
    expect(NowLog.parse('Started Gym')!.what, 'Gym');
    expect(NowLog.parse("I'm starting to study")!.text, 'Started study');
    expect(NowLog.parse('Back home')!.text, 'Back home');
    expect(NowLog.parse("I'm back")!.text, 'Back');
    expect(NowLog.parse('just woke up')!.verb, 'wake');
    expect(NowLog.parse('going to sleep')!.verb, 'sleep');
    expect(NowLog.parse('finished the report')!.what, 'the report');
    expect(NowLog.parse('start gym at 6 pm'), isNull);
    expect(NowLog.parse('finish the report tomorrow'), isNull);
    expect(NowLog.parse('buy milk'), isNull);
    expect(NowLog.parse('reading the news', forced: true)!.text, 'Started reading the news');
    expect(Destination.of('now: reading')!.type, 'now');
  });

  test('saying you finished a task marks it done and logs it', () async {
    final s = await _store();
    s.list('items').add(_planned(1, 'Write report', 9, 60));
    final said = await s.logNow(NowLog.parse('finished the report')!);
    expect(said, contains('Marked "Write report" done'));
    expect(s.list('items').single['status'], 'done');
    expect(s.list('log').single['text'], 'Finished the report');
  });

  test('a note in the chat like "started gym" is logged on the phone, without the AI', () async {
    final s = await _store();
    await Brain.capture(s, 'started gym');
    expect(s.list('log').single['text'], 'Started gym');
    expect(s.list('captures').single['reply'], contains('Started gym'));
  });

  test('a check-in is due when a planned block ends', () {
    expect(CheckIn.at(_planned(1, 'Study', 9, 45)), _ms(9, 45));
    expect(CheckIn.at({..._planned(1, 'Study', 9, 45), 'planned': null}), isNull);
    expect(CheckIn.at(_planned(1, 'Study', 9, 45, status: 'done')), isNull);
    expect(CheckIn.isSkip('Skipped'), isTrue);
    expect(CheckIn.isSkip('watched YouTube'), isFalse);
  });

  test('check-in answers: done, 15 more minutes, skipped, and what you did instead', () async {
    final s = await _store();
    s.list('items').addAll([
      _planned(1, 'Study', 9, 60),
      _planned(2, 'Gym', 11, 60),
      _planned(3, 'Read', 13, 30),
      _planned(4, 'Email', 14, 30),
    ]);
    await s.applyCheck(501, 'done', '', _ms(10));
    expect(s.byId('items', 1)!['status'], 'done');

    await s.applyCheck(502, 'more', '', _ms(12, 5));
    expect(s.byId('items', 2)!['est'], 80); // until 12:20, 15 minutes after the answer

    await s.applyCheck(503, 'other', 'Skipped', _ms(13, 30));
    final read = s.byId('items', 3)!;
    expect(read['skipped'], dayKey(_today));
    expect(read['planned'], isNull);
    expect(read['status'], 'open');

    await s.applyCheck(504, 'other', 'watched YouTube', _ms(14, 30));
    expect(s.list('log').map((e) => e['text']), containsAll(['Done: Study', 'Skipped: Read', 'Instead of Email: watched YouTube']));
  });

  test('plan vs reality: done, skipped, still to come, and how far behind', () {
    final now = _at(15);
    final items = [
      _planned(1, 'Study', 9, 60, status: 'done'),
      _planned(2, 'Gym', 13, 45),
      _planned(3, 'Call mom', 18, 30),
      {..._planned(4, 'Read', 11, 30), 'planned': null, 'skipped': dayKey(_today)},
      {..._planned(5, 'Unplanned', 10, 30), 'planned': null},
    ];
    final c = PlanCheck.of(items, now, dayKey(_today));
    expect([c.planned, c.done, c.skipped, c.toCome, c.late.length, c.behind], [4, 1, 1, 1, 1, 45]);
    expect(c.summary, 'Behind by 45 min: 1 block not done');
    expect(PlanCheck.of(items, _at(10), dayKey(_today)).summary, 'On track: 1 of 4 done, 1 skipped');
  });

  test('the timeline: what you started runs until the next thing, app stretches join, short ones are left out', () {
    Map<String, Object> app(String name, int h1, int m1, int h2, int m2) =>
        {'pkg': name.toLowerCase(), 'name': name, 'start': _ms(h1, m1), 'end': _ms(h2, m2)};
    final apps = [app('YouTube', 10, 0, 10, 10), app('YouTube', 10, 11, 10, 30), app('Chrome', 11, 0, 11, 3)]
        .map(AppSession.from)
        .whereType<AppSession>()
        .toList();
    final log = [
      {'id': 1, 'at': _ms(8), 'kind': 'now', 'verb': 'start', 'text': 'Started gym'},
      {'id': 2, 'at': _ms(9), 'kind': 'now', 'verb': 'back', 'text': 'Back home'},
    ];
    final items = [
      {..._planned(9, 'Write report', 12, 60, status: 'done'), 'doneAt': _ms(13)},
    ];
    final t = DayLog.timeline(_today, log: log, items: items, apps: apps);
    expect(t.map((m) => m.text), ['Started gym', 'Back home', 'YouTube', 'Done: Write report']);
    expect(t.first.end, _at(9));
    expect(t[2].end!.difference(t[2].at).inMinutes, 30);
    expect(AppSession.totals(apps).first.name, 'YouTube');
  });

  test('app alarms read plainly, and only the ones that are on go to the phone', () {
    final a = {'id': 1, 'pkg': 'com.google.android.youtube', 'name': 'YouTube', 'when': 'today', 'min': 80, 'ring': true};
    expect(AppAlarm.describe(a), 'YouTube over 1h 20m today');
    expect(AppAlarm.describe({...a, 'when': 'open'}), 'When I open YouTube');
    final phone = AppAlarm.forPhone([a, {...a, 'id': 2, 'on': false}]);
    expect(phone.single['text'], 'YouTube over 1h 20m today');
    expect(phone.single['ring'], true);
  });

  testWidgets('Your day fits a phone: behind card, quick log, timeline and apps', (t) async {
    final s = await _store(sessions: [
      {'pkg': 'com.google.android.youtube', 'name': 'YouTube', 'start': _ms(0, 10), 'end': _ms(0, 50)},
    ]);
    final now = DateTime.now();
    // A block that ended a little while ago (or just after midnight when the test runs early).
    final start = now.subtract(const Duration(minutes: 40));
    s.list('items').add({
      ..._planned(1, 'Study for the physics exam tomorrow morning', 0, 30),
      'when': (start.day == now.day ? start : DateTime(now.year, now.month, now.day)).millisecondsSinceEpoch,
    });
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: DayPage(store: s)));
    await t.pumpAndSettle();
    expect(find.text('Your day'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'started gym');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(s.list('log').single['text'], 'Started gym');

    if (find.text('Skipped').evaluate().isNotEmpty) {
      await t.tap(find.text('Skipped'));
      await t.pumpAndSettle();
      expect(s.byId('items', 1)!['skipped'], dayKey(now));
    }
    await t.scrollUntilVisible(find.text('Ask when a planned block ends'), 200, scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    expect(find.text('YouTube'), findsWidgets);
  });

  testWidgets('an app alarm can be set on a phone screen: YouTube over 80 minutes today, as an alarm', (t) async {
    final s = await _store();
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(body: Center(child: TextButton(onPressed: () => showAppAlarmEditor(context, s), child: const Text('Open'))))),
    ));
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    await t.tap(find.text('Choose an app'));
    await t.pumpAndSettle();
    await t.tap(find.text('YouTube'));
    await t.pumpAndSettle();
    await t.tap(find.text('Over a time today'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Minutes'), '80');
    await t.tap(find.text('Alarm on the full screen'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Add'));
    await t.tap(find.text('Add'));
    await t.pumpAndSettle();
    final a = s.list('appAlarms').single;
    expect([a['pkg'], a['when'], a['min'], a['ring']], ['com.google.android.youtube', 'today', 80, true]);
  });

  test('Done blocks: started until stopped or the next thing, sleep until waking, your buttons only when stopped', () {
    final log = <Rec>[
      {'id': 1, 'kind': 'now', 'verb': 'sleep', 'text': 'Going to sleep', 'at': _ms(0, 30)},
      {'id': 2, 'kind': 'now', 'verb': 'wake', 'text': 'Woke up', 'at': _ms(7)},
      {'id': 3, 'kind': 'now', 'verb': 'start', 'text': 'Started gym', 'at': _ms(8)},
      {'id': 4, 'kind': 'now', 'verb': 'start', 'text': 'Started Tuition', 'at': _ms(8, 30), 'act': 9},
      {'id': 5, 'kind': 'now', 'verb': 'back', 'text': 'Back home', 'at': _ms(9)},
      {'id': 6, 'kind': 'now', 'verb': 'start', 'text': 'Started reading', 'at': _ms(10), 'end': _ms(10, 45)},
    ];
    final b = DayLog.blocks(log, _at(0), _at(24), now: _at(11));
    String show(DoneBlock x) => '${x.title} ${DateTime.fromMillisecondsSinceEpoch(x.start).hour}-'
        '${DateTime.fromMillisecondsSinceEpoch(x.end).hour}:${DateTime.fromMillisecondsSinceEpoch(x.end).minute}${x.running ? ' running' : ''}';
    expect(b.map(show), ['Sleep 0-7:0', 'Gym 8-9:0', 'Tuition 8-11:0 running', 'Back home 9-10:0', 'Reading 10-10:45']);
    expect(DayLog.running(log, 9)?['id'], 4);
    expect(DayLog.running(log, 8), isNull);
  });

  test('your own buttons: start, stop, "finished tuition" ends it, and adding one afterwards', () async {
    final s = await _store();
    s.list('acts').add({'id': 9, 'name': 'Tuition'});
    s.startAct(s.list('acts').single);
    final run = DayLog.running(s.list('log'), 9)!;
    await s.stopLog(run, at: (run['at'] as int) + 3600000);
    expect(DayLog.running(s.list('log'), 9), isNull);

    await s.logNow(NowLog.parse('started tuition')!);
    expect(s.list('log').last['act'], 9);
    await s.logNow(NowLog.parse('finished tuition')!);
    expect(s.list('log').where((e) => e['act'] == 9 && e['end'] == null), isEmpty);

    s.addDone('YouTube', _ms(6), _ms(7));
    final y = DayLog.blocks(s.list('log'), _at(0), _at(24), now: _at(23)).firstWhere((x) => x.title == 'YouTube');
    expect([y.start, y.end, y.running], [_ms(6), _ms(7), false]);
  });
}
