import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/phone_calendar.dart';
import 'package:jarcis/store.dart';

Rec event({int id = 1, String title = 'Class', DateTime? when, int? dur = 90, bool allDay = false, int? span, String? repeat, List<String>? skip}) => {
      'id': id,
      'kind': 'event',
      'title': title,
      'when': (when ?? DateTime(2026, 11, 12, 9)).millisecondsSinceEpoch,
      'status': 'open',
      'dur': dur,
      'allDay': allDay,
      'span': span,
      'repeat': repeat,
      'skip': skip,
      'lead': 10,
    };

Map<String, dynamic> onPhone(Rec item, int ev) => {...CalMirror.toPhone(item), 'ev': ev};

void main() {
  test('only timed events that belong to Jarvis go to the phone', () {
    expect(CalMirror.eligible(event()), isTrue);
    expect(CalMirror.eligible({...event(), 'kind': 'task'}), isFalse);
    expect(CalMirror.eligible({...event(), 'kind': 'alarm'}), isFalse);
    expect(CalMirror.eligible({...event(), 'status': 'cancelled'}), isFalse);
    expect(CalMirror.eligible({...event(), 'habitId': 3}), isFalse);
    expect(CalMirror.eligible({...event(), 'ext': {'ev': 1}}), isFalse);
    expect(CalMirror.eligible({...event(), 'when': null}), isFalse);
  });

  test('a timed event runs from its start for its length', () {
    final p = CalMirror.toPhone(event());
    expect(p['start'], DateTime(2026, 11, 12, 9).millisecondsSinceEpoch);
    expect(p['end'], DateTime(2026, 11, 12, 10, 30).millisecondsSinceEpoch);
    expect(p['allDay'], isFalse);
  });

  test('an all-day event runs between UTC midnights, to the day after its last day', () {
    final p = CalMirror.toPhone(event(allDay: true, dur: null, span: 3));
    expect(p['start'], DateTime.utc(2026, 11, 12).millisecondsSinceEpoch);
    expect(p['end'], DateTime.utc(2026, 11, 15).millisecondsSinceEpoch);
  });

  test('skipped dates of a repeat go over as that day at the event time', () {
    final p = CalMirror.toPhone(event(repeat: 'weekly', skip: ['2026-11-19']));
    expect(p['skip'], [DateTime(2026, 11, 19, 9).millisecondsSinceEpoch]);
    expect(CalMirror.toPhone(event(skip: ['2026-11-19']))['skip'], isEmpty); // no repeat, nothing to skip
  });

  test('the signature moves with what the phone shows, and only that', () {
    final a = CalMirror.signature(event());
    expect(CalMirror.signature(event()), a);
    expect(CalMirror.signature(event(title: 'Lab')), isNot(a));
    expect(CalMirror.signature(event(dur: 60)), isNot(a));
    expect(CalMirror.signature({...event(), 'lead': 30, 'priority': 2}), a);
  });

  test('a phone event comes back as Jarvis fields, timed and all-day', () {
    final t = CalMirror.fromPhone(onPhone(event(), 5));
    expect(t['when'], DateTime(2026, 11, 12, 9).millisecondsSinceEpoch);
    expect(t['dur'], 90);
    expect(t['allDay'], isFalse);
    final d = CalMirror.fromPhone(onPhone(event(allDay: true, dur: null, span: 3), 5));
    expect(d['when'], DateTime(2026, 11, 12).millisecondsSinceEpoch);
    expect(d['allDay'], isTrue);
    expect(d['span'], 3);
    expect(d['dur'], isNull);
    expect(CalMirror.fromPhone(onPhone(event(allDay: true, dur: null), 5))['span'], isNull);
  });

  test('an event from the phone has a negative id, its own marker and its colour', () {
    final e = CalMirror.external({'ev': 7, 'cal': 2, 'title': 'Dentist', 'start': DateTime(2026, 11, 14, 15).millisecondsSinceEpoch, 'end': DateTime(2026, 11, 14, 16).millisecondsSinceEpoch, 'allDay': false, 'color': 0xFF123456});
    expect((e['id'] as int) < 0, isTrue);
    expect(e['ext'], {'ev': 7, 'cal': 2});
    expect(e['extColor'], 0xFF123456);
    expect(CalMirror.eligible(e), isFalse);
    // the same event on another day is a different item
    final f = CalMirror.external({'ev': 7, 'cal': 2, 'title': 'Dentist', 'start': DateTime(2026, 11, 21, 15).millisecondsSinceEpoch, 'end': DateTime(2026, 11, 21, 16).millisecondsSinceEpoch, 'allDay': false, 'color': 0});
    expect(f['id'], isNot(e['id']));
  });

  group('plan', () {
    final it = event();
    Map<String, dynamic> linked({int? jsig, int? psig}) => {
          '1': {'ev': 5, 'jsig': jsig ?? CalMirror.signature(it), 'psig': psig ?? CalMirror.phoneSig(onPhone(it, 5))},
        };

    List<String> run(List<Rec> items, Map<String, dynamic> links, Map<int, Map<String, dynamic>> phone, {bool canWrite = true}) =>
        [for (final o in CalMirror.plan(items: items, links: links, phone: phone, canWrite: canWrite)) '$o'];

    test('a new event is created on the phone, if a calendar was chosen', () {
      expect(run([it], {}, {}), ['create 1']);
      expect(run([it], {}, {}, canWrite: false), isEmpty);
    });

    test('nothing to do when neither side changed', () {
      expect(run([it], linked(), {5: onPhone(it, 5)}), isEmpty);
    });

    test('a change in Jarvis goes to the phone', () {
      expect(run([event(title: 'Lab')], linked(), {5: onPhone(it, 5)}), ['update 1']);
    });

    test('a change on the phone comes to Jarvis', () {
      expect(run([it], linked(), {5: onPhone(event(title: 'Lab'), 5)}), ['pull 1']);
    });

    test('when both changed, Jarvis wins', () {
      expect(run([event(dur: 30)], linked(), {5: onPhone(event(title: 'Lab'), 5)}), ['update 1']);
    });

    test('an event deleted on the phone is let go, not deleted in Jarvis and not made again', () {
      expect(run([it], linked(), {}), ['forget 1']);
      expect(run([it], {'1': {'off': true}}, {}), isEmpty);
    });

    test('an event gone from Jarvis, or no longer one, is removed from the phone', () {
      expect(run([], linked(), {5: onPhone(it, 5)}), ['remove 5']);
      expect(run([{...it, 'status': 'cancelled'}], linked(), {5: onPhone(it, 5)}), ['remove 5']);
      expect(run([{...it, 'kind': 'task'}], linked(), {5: onPhone(it, 5)}), ['remove 5']);
    });

    test('a let-go event that is deleted in Jarvis has nothing to remove', () {
      expect(run([], {'1': {'off': true}}, {}), isEmpty);
    });
  });
}
