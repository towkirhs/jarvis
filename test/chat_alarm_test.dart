import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/brain.dart';
import 'package:jarcis/clock.dart';
import 'package:jarcis/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _tomorrow = DateTime.now().add(const Duration(days: 1));
String get _date => '${_tomorrow.year}-${two(_tomorrow.month)}-${two(_tomorrow.day)}';
int _at(int h, [int m = 0]) => DateTime(_tomorrow.year, _tomorrow.month, _tomorrow.day, h, m).millisecondsSinceEpoch;

Future<Store> _store() async {
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (call) async => null);
  final s = Store();
  await s.load();
  return s;
}

Future<String?> _say(Store s, Map<String, dynamic> p, List<Map<String, dynamic>> undo) =>
    Brain.applyParsed(s, p, 1, const [], undo);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('which titles are just an alarm', () {
    for (final t in ['Alarm', 'alarm', 'Wake up', 'wake me up', '9 am alarm', 'Morning alarm', 'Alarm at 7']) {
      expect(Clock.plainAlarm(t), isTrue, reason: t);
    }
    for (final t in ['Call mom', 'Bd vs Bhutan match', 'Take medicine']) {
      expect(Clock.plainAlarm(t), isFalse, reason: t);
    }
  });

  test('"set alarm 5 am" is only a Clock alarm', () async {
    final s = await _store();
    final undo = <Map<String, dynamic>>[];
    final said = await _say(s, {'type': 'alarm', 'title': 'Alarm', 'date': _date, 'time': '05:00'}, undo);
    final c = s.list('clocks').single;
    expect([c['time'], c['on'], c['days'], c['label'], c['at']], ['05:00', true, <int>[], '', _at(5)]);
    expect(s.list('items'), isEmpty);
    expect(said, startsWith('Alarm: '));
    expect(await _say(s, {'type': 'alarm', 'title': 'Alarm', 'date': _date, 'time': '05:00'}, undo), startsWith('Already have'));
  });

  test('an alarm about something makes a linked task; finishing the task turns the alarm off; deleting it removes both', () async {
    final s = await _store();
    final said = await _say(s, {'type': 'alarm', 'title': 'Call mom', 'date': _date, 'time': '19:00'}, []);
    expect(said, endsWith('with a linked task'));
    final c = s.list('clocks').single;
    final task = s.list('items').single;
    expect([task['kind'], task['title'], task['when'], task['clock']], ['task', 'Call mom', _at(19), c['id']]);
    expect([c['label'], c['item']], ['Call mom', task['id']]);

    task['when'] = _at(20, 30);
    await s.syncRecord('items', task);
    expect([c['at'], c['time']], [_at(20, 30), '20:30']);

    await s.markDone(task);
    expect(c['on'], isFalse);

    final s2 = await _store();
    await _say(s2, {'type': 'alarm', 'title': 'Call mom', 'date': _date, 'time': '19:00'}, []);
    s2.removeRec('items', s2.list('items').single, 'Deleted');
    expect(s2.list('clocks'), isEmpty);
    await s2.undo(s2.list('actions').last['id'] as int);
    expect([s2.list('items').length, s2.list('clocks').length], [1, 1]);
  });

  test('an alarm for an event joins the event and keeps its 15 minutes before when the event moves', () async {
    final s = await _store();
    await _say(s, {'type': 'event', 'title': 'Bd vs Bhutan match', 'date': _date, 'time': '20:00'}, []);
    final said = await _say(s, {'type': 'alarm', 'title': 'Bd vs Bhutan match', 'date': _date, 'time': '19:45'}, []);
    expect(said, endsWith('linked to the event'));
    final event = s.list('items').single;
    final c = s.list('clocks').single;
    expect(event['clock'], c['id']);
    event['when'] = _at(21);
    await s.syncRecord('items', event);
    expect(c['time'], '20:45');
  });

  test('"just an alarm" makes no task', () async {
    final s = await _store();
    await _say(s, {'type': 'alarm', 'title': 'Take medicine', 'date': _date, 'time': '22:00', 'alarmOnly': true}, []);
    expect([s.list('clocks').single['label'], s.list('items').length], ['Take medicine', 0]);
  });
}
