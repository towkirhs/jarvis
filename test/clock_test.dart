import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/clock.dart';

void main() {
  // Saturday 7 Nov 2026, 22:30.
  final now = DateTime(2026, 11, 7, 22, 30);

  test('a one-time alarm rings at the next time it comes', () {
    expect(Clock.next('23:00', [], now), DateTime(2026, 11, 7, 23));
    expect(Clock.next('07:00', [], now), DateTime(2026, 11, 8, 7));
    expect(Clock.next('22:30', [], now), DateTime(2026, 11, 8, 22, 30)); // not this very minute
  });

  test('a repeating alarm skips days not chosen', () {
    // Sunday to Thursday, the Bangladesh work week.
    final workWeek = [7, 1, 2, 3, 4];
    expect(Clock.next('07:00', workWeek, now), DateTime(2026, 11, 8, 7)); // Sunday
    expect(Clock.next('07:00', [5], now), DateTime(2026, 11, 13, 7)); // next Friday
    expect(Clock.next('23:00', [6], now), DateTime(2026, 11, 7, 23)); // later today, a Saturday
    expect(Clock.next('22:00', [6], now), DateTime(2026, 11, 14, 22)); // today's has passed
  });

  test('weekdays become bits for the phone, Monday first', () {
    expect(Clock.mask([]), 0);
    expect(Clock.mask([1]), 1);
    expect(Clock.mask([7]), 64);
    expect(Clock.mask([1, 2, 3, 4, 5, 6, 7]), 127);
  });

  test('describes days and time left', () {
    expect(Clock.daysText([]), 'Once');
    expect(Clock.daysText([1, 2, 3, 4, 5, 6, 7]), 'Every day');
    expect(Clock.daysText([7, 1, 3]), 'Mon, Wed, Sun');
    expect(Clock.until(DateTime(2026, 11, 8, 7), now), 'in 8 h 30 min');
    expect(Clock.until(DateTime(2026, 11, 7, 22, 45), now), 'in 15 min');
    expect(Clock.until(DateTime(2026, 11, 13, 7), now), 'in 5 days');
  });

  test('the phone watches place alarms that are on and open tasks with a place', () {
    final places = [
      {'id': 1, 'name': 'Home', 'lat': 23.75, 'lng': 90.39, 'radius': 150},
      {'id': 2, 'name': 'Office', 'lat': 23.79, 'lng': 90.40},
    ];
    final clocks = [
      {'id': 10, 'label': 'Get off', 'on': true, 'place': 2, 'when': 'arrive', 'sound': '/x.mp3'},
      {'id': 11, 'label': 'Off one', 'on': false, 'place': 1},
      {'id': 12, 'label': 'Time alarm', 'on': true, 'time': '07:00'},
      {'id': 13, 'label': 'Gone place', 'on': true, 'place': 99},
      {'id': 14, 'label': 'Every time', 'on': true, 'place': 1, 'when': 'leave', 'once': false},
    ];
    final items = [
      {'id': 20, 'nid': 21, 'title': 'Buy milk', 'status': 'open', 'place': 1, 'placeWhen': 'arrive'},
      {'id': 22, 'nid': 23, 'title': 'Done one', 'status': 'done', 'place': 1},
      {'id': 24, 'nid': 25, 'title': 'No place', 'status': 'open'},
    ];
    final f = Clock.fences(clocks, items, places);
    expect(f.map((e) => e['key']), ['clock:10', 'clock:14', 'item:20']);
    expect(f[0], {
      'key': 'clock:10', 'kind': 'alarm', 'id': 10, 'label': 'Get off', 'place': 'Office', 'lat': 23.79,
      'lng': 90.40, 'radius': 200, 'when': 'arrive', 'sound': '/x.mp3', 'once': true,
    });
    expect(f[1]['once'], false);
    expect(f[1]['when'], 'leave');
    expect(f[2]['kind'], 'task');
    expect(f[2]['id'], 21); // the item's notification id, so Done in the notification finishes it
    expect(f[2]['radius'], 150);
  });
}
