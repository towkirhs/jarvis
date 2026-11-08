import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/ics.dart';

void main() {
  final when = DateTime(2026, 11, 10, 15, 30).millisecondsSinceEpoch;
  Map<String, dynamic> ev(Map<String, dynamic> o) =>
      {'id': 7, 'title': 'Physics', 'kind': 'event', 'when': when, 'status': 'open', ...o};

  test('export then import gives the event back', () {
    final text = Ics.export([ev({'dur': 90, 'desc': 'Room 4, bring notes', 'tags': ['school', 'a;b'], 'repeat': 'weekly', 'lead': 15})]);
    expect(text, contains('BEGIN:VEVENT'));
    expect(text, contains('UID:jarvis-7@jarcis'));
    expect(text, contains('TRIGGER:-PT15M'));
    expect(text.contains('\r\n'), isTrue);
    final e = Ics.parse(text).single;
    expect(e.title, 'Physics');
    expect(e.start, DateTime.fromMillisecondsSinceEpoch(when));
    expect(e.minutes, 90);
    expect(e.repeat, 'weekly');
    expect(e.lead, 15);
    expect(e.desc, 'Room 4, bring notes');
    expect(e.tags, ['school', 'a;b']);
    expect(e.uid, 'jarvis-7@jarcis');
  });

  test('all-day events use dates', () {
    final text = Ics.export([ev({'allDay': true})]);
    expect(text, contains('DTSTART;VALUE=DATE:20261110'));
    expect(text, contains('DTEND;VALUE=DATE:20261111'));
    final e = Ics.parse(text).single;
    expect(e.allDay, isTrue);
    expect(e.start, DateTime(2026, 11, 10));
  });

  test('tasks with a date become VTODO; alarms and undated are left out', () {
    final text = Ics.export([
      ev({'kind': 'task', 'title': 'Pay rent', 'id': 1}),
      ev({'kind': 'alarm', 'id': 2}),
      ev({'when': null, 'id': 3}),
      ev({'status': 'cancelled', 'id': 4}),
    ]);
    expect(text, contains('BEGIN:VTODO'));
    expect(text, contains('DUE:'));
    expect('BEGIN:VEVENT'.allMatches(text), isEmpty);
    final e = Ics.parse(text).single;
    expect(e.todo, isTrue);
    expect(e.title, 'Pay rent');
  });

  test('long lines fold at 75 bytes and unfold again', () {
    final title = 'é' * 80;
    final text = Ics.export([ev({'title': title})]);
    for (final line in text.split('\r\n')) {
      expect(line.runes.fold<int>(0, (n, r) => n + String.fromCharCode(r).codeUnits.length) <= 76, isTrue);
    }
    expect(Ics.parse(text).single.title, title);
  });

  test('escaping', () {
    expect(Ics.escape('a,b;c\\d\ne'), 'a\\,b\;c\\\\d\\ne');
    expect(Ics.unescape('a\\,b\;c\\\\d\\ne'), 'a,b;c\\d\ne');
  });

  const wrap = 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n';
  String cal(String body) => '${wrap}BEGIN:VEVENT\r\n$body\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';

  test('floating and named-zone times are local; Z times are converted', () {
    expect(Ics.parse(cal('SUMMARY:A\r\nDTSTART:20261109T150000')).single.start, DateTime(2026, 11, 9, 15));
    expect(Ics.parse(cal('SUMMARY:A\r\nDTSTART;TZID=Asia/Dhaka:20261109T150000')).single.start, DateTime(2026, 11, 9, 15));
    expect(Ics.parse(cal('SUMMARY:A\r\nDTSTART:20261109T090000Z')).single.start, DateTime.utc(2026, 11, 9, 9).toLocal());
  });

  test('end time and duration give the length', () {
    expect(Ics.parse(cal('SUMMARY:A\r\nDTSTART:20261109T150000\r\nDTEND:20261109T164500')).single.minutes, 105);
    expect(Ics.parse(cal('SUMMARY:A\r\nDTSTART:20261109T150000\r\nDURATION:PT1H30M')).single.minutes, 90);
    expect(Ics.duration('P1D'), 1440);
    expect(Ics.duration('-PT15M'), -15);
    expect(Ics.duration('nonsense'), isNull);
  });

  test('simple rules repeat, complex ones are flagged', () {
    expect(Ics.rule('FREQ=DAILY'), ('daily', false));
    expect(Ics.rule('FREQ=YEARLY;INTERVAL=1'), ('yearly', false));
    expect(Ics.rule('FREQ=WEEKLY;INTERVAL=2'), (null, true));
    expect(Ics.rule('FREQ=WEEKLY;BYDAY=MO,WE'), (null, true));
    expect(Ics.rule('FREQ=DAILY;COUNT=5'), (null, true));
  });

  test('alarm trigger is read as the reminder, and does not leak into the event', () {
    final e = Ics.parse(cal('SUMMARY:A\r\nDTSTART:20261109T150000\r\nBEGIN:VALARM\r\nTRIGGER:-PT30M\r\nDESCRIPTION:ignore me\r\nEND:VALARM')).single;
    expect(e.lead, 30);
    expect(e.desc, isNull);
  });

  test('cancelled, completed and start-less items are skipped', () {
    expect(Ics.parse(cal('SUMMARY:A\r\nSTATUS:CANCELLED\r\nDTSTART:20261109T150000')), isEmpty);
    expect(Ics.parse(cal('SUMMARY:A')), isEmpty);
    expect(Ics.parse('not a calendar'), isEmpty);
  });

  test('a to-do uses its due time', () {
    const t = 'BEGIN:VCALENDAR\r\nBEGIN:VTODO\r\nSUMMARY:Buy milk\r\nDUE:20261109T180000\r\nEND:VTODO\r\nEND:VCALENDAR';
    final e = Ics.parse(t).single;
    expect(e.todo, isTrue);
    expect(e.start, DateTime(2026, 11, 9, 18));
  });

  test('a folded line is joined', () {
    final e = Ics.parse(cal('SUMMARY:Hello\r\n  world\r\nDTSTART:20261109T150000')).single;
    expect(e.title, 'Hello world');
  });
}
