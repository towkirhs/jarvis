import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/cal_index.dart';
import 'package:jarcis/store.dart';

Rec item(int id, DateTime when, {String? repeat, String status = 'open', bool allDay = false, int? span, List<String>? skip, int? dur}) => {
      'id': id,
      'kind': 'event',
      'title': 'T$id',
      'when': when.millisecondsSinceEpoch,
      'status': status,
      'repeat': repeat,
      'allDay': allDay,
      if (span != null) 'span': span,
      if (skip != null) 'skip': skip,
      if (dur != null) 'dur': dur,
    };

List<String> ids(Map<String, List<CalEntry>> m, String day) => [for (final e in m[day] ?? const <CalEntry>[]) 'T${e.item['id']}'];

void main() {
  final from = DateTime(2026, 11, 1);
  final to = DateTime(2026, 11, 30);

  test('a plain item sits on its own day only', () {
    final m = CalIndex.build([item(1, DateTime(2026, 11, 12, 9))], from, to);
    expect(ids(m, '2026-11-12'), ['T1']);
    expect(m.length, 1);
  });

  test('cancelled items and items with no time are left out', () {
    final none = {'id': 2, 'kind': 'task', 'title': 'x', 'when': null, 'status': 'open'};
    final m = CalIndex.build([item(1, DateTime(2026, 11, 12, 9), status: 'cancelled'), none], from, to);
    expect(m, isEmpty);
  });

  test('a weekly item shows on every week from its stored date, and never before it', () {
    final m = CalIndex.build([item(1, DateTime(2026, 11, 10, 18), repeat: 'weekly')], from, to);
    expect(m.keys.toList()..sort(), ['2026-11-10', '2026-11-17', '2026-11-24']);
    expect(m['2026-11-10']!.single.repeated, isFalse);
    expect(m['2026-11-17']!.single.repeated, isTrue);
    expect(m['2026-11-17']!.single.start, DateTime(2026, 11, 17, 18));
  });

  test('a daily item skips the dates in its skip list', () {
    final m = CalIndex.build(
      [item(1, DateTime(2026, 11, 20, 7), repeat: 'daily', skip: ['2026-11-22'])],
      from,
      to,
    );
    expect(m.containsKey('2026-11-22'), isFalse);
    expect(m.containsKey('2026-11-21'), isTrue);
    expect(m.containsKey('2026-11-23'), isTrue);
    expect(m.length, 10 /* 20..30 is eleven days, minus the skipped one */);
  });

  test('a monthly item on the 31st lands on the last day of shorter months', () {
    final m = CalIndex.build(
      [item(1, DateTime(2026, 1, 31, 9), repeat: 'monthly')],
      DateTime(2026, 1, 1),
      DateTime(2026, 4, 30),
    );
    expect(m.keys.toList()..sort(), ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30']);
  });

  test('a yearly item on 29 February lands on 28 February in other years', () {
    final m = CalIndex.build(
      [item(1, DateTime(2024, 2, 29, 9), repeat: 'yearly')],
      DateTime(2025, 1, 1),
      DateTime(2026, 12, 31),
    );
    expect(m.keys.toList()..sort(), ['2025-02-28', '2026-02-28']);
  });

  test('an all-day item with a span of three covers three days', () {
    final m = CalIndex.build([item(1, DateTime(2026, 11, 5), allDay: true, span: 3)], from, to);
    expect(m.keys.toList()..sort(), ['2026-11-05', '2026-11-06', '2026-11-07']);
    expect(m['2026-11-05']!.single.firstDay, isTrue);
    expect(m['2026-11-07']!.single.firstDay, isFalse);
  });

  test('a span that starts before the window still shows inside it', () {
    final m = CalIndex.build([item(1, DateTime(2026, 10, 30), allDay: true, span: 3)], from, to);
    expect(m.keys.toList()..sort(), ['2026-11-01']);
  });

  test('each day is sorted: all-day first, then by start time', () {
    final m = CalIndex.build([
      item(1, DateTime(2026, 11, 12, 15)),
      item(2, DateTime(2026, 11, 12, 8)),
      item(3, DateTime(2026, 11, 12), allDay: true),
    ], from, to);
    expect(ids(m, '2026-11-12'), ['T3', 'T2', 'T1']);
  });

  test('done items still show (struck through by the views)', () {
    final m = CalIndex.build([item(1, DateTime(2026, 11, 12, 9), status: 'done')], from, to);
    expect(ids(m, '2026-11-12'), ['T1']);
  });

  test('a daily item over a long window stops at the cap', () {
    final m = CalIndex.build([item(1, DateTime(2020, 1, 1, 9), repeat: 'daily')], DateTime(2020, 1, 1), DateTime(2030, 1, 1));
    expect(m.length, CalIndex.maxPerItem);
  });

  test('the window is inclusive of both end days', () {
    final m = CalIndex.build(
      [item(1, DateTime(2026, 11, 1, 9), repeat: 'daily')],
      DateTime(2026, 11, 3),
      DateTime(2026, 11, 4),
    );
    expect(m.keys.toList()..sort(), ['2026-11-03', '2026-11-04']);
  });
}
