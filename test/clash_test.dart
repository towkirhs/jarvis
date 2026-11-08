import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/clash.dart';

void main() {
  int at(int h, [int m = 0]) => DateTime(2026, 11, 10, h, m).millisecondsSinceEpoch;
  Map<String, dynamic> ev(int id, int when, {int? dur, String kind = 'event', bool allDay = false, String status = 'open'}) =>
      {'id': id, 'title': 'E$id', 'kind': kind, 'when': when, 'dur': dur, 'allDay': allDay, 'status': status};
  String clock(int ms) => '${DateTime.fromMillisecondsSinceEpoch(ms).hour}h';

  group('Clash', () {
    test('overlap is found', () {
      expect(Clash.find([ev(1, at(9), dur: 120)], at(10), 60).length, 1);
    });
    test('events that only touch do not clash', () {
      expect(Clash.find([ev(1, at(9), dur: 60)], at(10), 60), isEmpty);
      expect(Clash.find([ev(1, at(11))], at(10), 60), isEmpty);
    });
    test('default length is an hour', () {
      expect(Clash.find([ev(1, at(9))], at(9, 30), 30).length, 1);
      expect(Clash.find([ev(1, at(9))], at(10, 1), 30), isEmpty);
    });
    test('the event being edited is ignored', () {
      expect(Clash.find([ev(1, at(9))], at(9), 60, excludeId: 1), isEmpty);
    });
    test('all-day, tasks, alarms, done and cancelled never clash', () {
      final items = [
        ev(1, at(9), allDay: true),
        ev(2, at(9), kind: 'task'),
        ev(3, at(9), kind: 'alarm'),
        ev(4, at(9), status: 'done'),
        ev(5, at(9), status: 'cancelled'),
      ];
      expect(Clash.find(items, at(9), 60), isEmpty);
    });
    test('sorted by start, and the sentence says who', () {
      final found = Clash.find([ev(2, at(10), dur: 120), ev(1, at(9), dur: 120)], at(10), 60);
      expect([for (final f in found) f['id']], [1, 2]);
      expect(Clash.sentence(found, clock), 'Clashes with E1 (9h to 11h) and E2 (10h to 12h)');
      expect(Clash.sentence([], clock), '');
    });
    test('a long list is shortened', () {
      final many = [for (var i = 1; i <= 4; i++) ev(i, at(9), dur: 60)];
      expect(Clash.sentence(Clash.find(many, at(9), 60), clock), endsWith('and 2 more'));
    });
  });

  group('Lead', () {
    test('names', () {
      expect(Lead.name(0), 'At the time');
      expect(Lead.name(15), '15 min before');
      expect(Lead.name(60), '1 hour before');
      expect(Lead.name(1440), '1 day before');
      expect(Lead.short(15), 'In 15 min');
      expect(Lead.short(1440), 'Tomorrow');
    });
    test('ids stay clear of the timer and alarms', () {
      expect(Lead.id(5), 1200000005);
      expect(Lead.id(100000000) < 1799999999, isTrue);
    });
    test('default is 10 minutes unless set', () {
      expect(Lead.defaultFor({}), 10);
      expect(Lead.defaultFor({'lead': 30}), 30);
      expect(Lead.defaultFor({'lead': 0}), 0);
    });
  });
}
