import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/backups.dart';
import 'package:jarcis/brain.dart';
import 'package:jarcis/categories.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/health_page.dart';
import 'package:jarcis/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _allOn = {'notifications': true, 'exact': true, 'battery': true, 'overlay': true, 'fullScreen': true, 'usage': false};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('daily backup files: their day, which old ones go, and what one holds', () {
    expect(Backups.name('2026-11-18'), 'jarvis-2026-11-18.json');
    expect(Backups.dayOf('jarvis-2026-11-18.json'), '2026-11-18');
    expect(Backups.dayOf('before-restore-123.json'), isNull);
    final names = [for (var d = 1; d <= 16; d++) Backups.name('2026-11-${d.toString().padLeft(2, '0')}')]..add('before-restore-1.json');
    expect(Backups.extra(names), ['jarvis-2026-11-01.json', 'jarvis-2026-11-02.json']);
    expect(Backups.summary({'items': [1, 2], 'habits': [1], 'tx': [], 'entries': [1, 2, 3]}),
        '2 tasks and events, 1 habits, 0 money entries, 3 journal entries');
    expect(() => Backups.parse('{"hello": 1}'), throwsFormatException);
    expect(Backups.parse('{"items": [], "captures": []}')['items'], isEmpty);
  });

  test('health check: what is fine, what needs fixing, and the background test', () {
    final now = DateTime(2026, 11, 18, 9);
    final good = HealthCheck.rows({..._allOn, 'beatAt': DateTime(2026, 11, 18, 3, 31).millisecondsSinceEpoch,
      'beatDue': DateTime(2026, 11, 18, 3, 30).millisecondsSinceEpoch}, now: now, lastBackupDay: '2026-11-18');
    expect(good.where((r) => r.state == 'fix'), isEmpty);
    expect(good.firstWhere((r) => r.title.startsWith('Usage')).state, 'info');
    expect(good.firstWhere((r) => r.title.startsWith('Background')).title, 'Background test ran on time');
    expect(good.last.title, 'Backed up today');

    final bad = HealthCheck.rows({..._allOn, 'battery': false, 'beatAt': DateTime(2026, 11, 16, 3, 30).millisecondsSinceEpoch},
        now: now, lastBackupDay: '2026-11-12', appAlarms: true);
    expect(bad.where((r) => r.state == 'fix').map((r) => r.title), [
      'Battery saving can stop Jarvis',
      'Usage access is off',
      'Background test did not run last night',
      'Last backup 6 days ago',
    ]);

    final late = HealthCheck.rows({..._allOn, 'beatAt': DateTime(2026, 11, 18, 5, 40).millisecondsSinceEpoch,
      'beatDue': DateTime(2026, 11, 18, 3, 30).millisecondsSinceEpoch}, now: now);
    expect(late.firstWhere((r) => r.title.startsWith('Background')).title, 'Background test ran 2 h late');
  });

  test('money categories in small letters get a capital, and keep it', () {
    final tx = [
      {'type': 'expense', 'cat': 'groceries'},
      {'type': 'expense', 'cat': 'Food'},
    ];
    expect(Cats.capitalAll(tx), 1);
    expect(tx.first['cat'], 'Groceries');
    expect(Cats.tidy('groceries', type: 'expense', rules: {}, known: ['groceries']), 'Groceries');
  });

  test('"buy scale alarm at 12" is an alarm and a task named "Buy scale"', () async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (call) async => null);
    final s = Store();
    await s.load();
    final t = DateTime.now().add(const Duration(days: 1));
    final date = '${t.year}-${two(t.month)}-${two(t.day)}';
    await Brain.applyParsed(s, {'type': 'alarm', 'title': 'Buy scale alarm', 'date': date, 'time': '12:00'}, 1, const [], []);
    expect(s.list('clocks').single['label'], 'Buy scale');
    expect(s.list('items').single['title'], 'Buy scale');
  });

  testWidgets('the Health check fits a phone and lists what to fix', (t) async {
    Haptics.on = false;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (call) async => switch (call.method) {
              'health' => {..._allOn, 'exact': false, 'beatAt': 0, 'beatDue': 0},
              _ => null,
            });
    final s = Store();
    await s.load();
    t.view.physicalSize = const Size(360, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: HealthPage(store: s)));
    await t.pumpAndSettle();
    expect(find.text('1 thing to fix'), findsOneWidget);
    expect(find.text('Exact alarms are not allowed'), findsOneWidget);
    expect(find.text('Fix'), findsOneWidget);
  });
}
