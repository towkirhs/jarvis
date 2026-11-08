import 'dart:convert';

import 'native.dart';
import 'store.dart';

/// The alarm clock and place triggers.
///
/// An alarm ('clocks') is either at a time: {id, label, on, sound, soundName, time: 'HH:MM', days: [1..7], at},
/// with days Monday = 1 … Sunday = 7 (none = once; 'at' is when a one-time alarm rings),
/// or at a place: {id, label, on, sound, soundName, place: place id, when: 'arrive' or 'leave', once}.
/// A place ('places'): {id, name, lat, lng, radius in metres}.
/// A task can have a place too: item 'place' (place id) and 'placeWhen' ('arrive' or 'leave').
class Clock {
  static const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// The next time [hhmm] comes, after [now], on one of [days] (any day if empty).
  static DateTime next(String hhmm, List<int> days, DateTime now) {
    final p = hhmm.split(':');
    var t = DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
    for (var i = 0; i < 8; i++) {
      if (t.isAfter(now) && (days.isEmpty || days.contains(t.weekday))) return t;
      t = DateTime(t.year, t.month, t.day + 1, t.hour, t.minute);
    }
    return t;
  }

  /// Weekdays as bits for the phone: Monday = bit 0 … Sunday = bit 6.
  static int mask(List<int> days) => days.fold(0, (m, d) => m | (1 << (d - 1)));

  static String daysText(List<int> days) {
    if (days.isEmpty) return 'Once';
    if (days.length == 7) return 'Every day';
    return ([...days]..sort()).map((d) => dayNames[d - 1]).join(', ');
  }

  /// "in 7 h 20 min", for after an alarm is set.
  static String until(DateTime t, DateTime now) {
    final m = (t.difference(now).inSeconds / 60).ceil();
    if (m < 60) return 'in $m min';
    if (m < 24 * 60) return 'in ${m ~/ 60} h${m % 60 == 0 ? '' : ' ${m % 60} min'}';
    final d = m ~/ (24 * 60);
    return 'in $d day${d == 1 ? '' : 's'}';
  }

  static List<int> days(Rec c) => ((c['days'] as List?) ?? const []).cast<int>();

  static Rec? place(List<Rec> places, Object? id) {
    for (final p in places) {
      if (p['id'] == id) return p;
    }
    return null;
  }

  /// What the phone should watch: place alarms that are on, and open tasks with a place.
  static List<Map<String, dynamic>> fences(List<Rec> clocks, List<Rec> items, List<Rec> places) {
    Map<String, dynamic>? fence(String key, String kind, int id, String label, Object? placeId, String? when,
        {String? sound, bool once = false}) {
      final p = place(places, placeId);
      if (p == null) return null;
      return {
        'key': key,
        'kind': kind,
        'id': id,
        'label': label,
        'place': p['name'],
        'lat': p['lat'],
        'lng': p['lng'],
        'radius': p['radius'] ?? 200,
        'when': when ?? 'arrive',
        'sound': sound,
        'once': once,
      };
    }

    return [
      for (final c in clocks)
        if (c['on'] == true && c['place'] != null)
          fence('clock:${c['id']}', 'alarm', c['id'] as int, (c['label'] as String?) ?? 'Alarm', c['place'],
              c['when'] as String?,
              sound: c['sound'] as String?, once: c['once'] != false),
      for (final i in items)
        if (i['status'] == 'open' && i['place'] != null && i['nid'] != null)
          fence('item:${i['id']}', 'task', i['nid'] as int, i['title'] as String, i['place'], i['placeWhen'] as String?),
    ].whereType<Map<String, dynamic>>().toList();
  }

  static String? _sentClocks;
  static String? _sentFences;

  /// Makes the phone's alarms and place triggers match the data. Cheap to call often: it only tells the phone
  /// what changed since the last call.
  static Future<void> sync(Store s) async {
    final now = DateTime.now();
    final clocks = s.list('clocks');
    var changed = false;
    final timed = <Map<String, dynamic>>[];
    for (final c in clocks) {
      if (c['time'] == null) continue;
      final days = Clock.days(c);
      // A one-time alarm that already rang switches itself off.
      if (c['on'] == true && days.isEmpty && c['at'] is int && (c['at'] as int) <= now.millisecondsSinceEpoch) {
        c['on'] = false;
        changed = true;
      }
      if (c['on'] != true) continue;
      if (days.isEmpty && c['at'] == null) {
        c['at'] = next(c['time'] as String, days, now).millisecondsSinceEpoch;
        changed = true;
      }
      timed.add({
        'id': c['id'],
        'millis': days.isEmpty ? c['at'] : next(c['time'] as String, days, now).millisecondsSinceEpoch,
        'label': (c['label'] as String?)?.isNotEmpty == true ? c['label'] : 'Alarm',
        'days': mask(days),
        'sound': c['sound'],
      });
    }
    if (changed) s.save();

    // Weekly alarms are compared without their next time, which moves on by itself.
    final sig = jsonEncode([
      for (final t in timed) {...t, if (t['days'] != 0) 'millis': null},
      for (final c in clocks) if (c['on'] != true) c['id'],
    ]);
    if (sig != _sentClocks) {
      _sentClocks = sig;
      for (final c in clocks) {
        if (c['time'] != null && c['on'] != true) await Native.cancel(c['id'] as int);
      }
      for (final t in timed) {
        await Native.clock(
          id: t['id'] as int,
          millis: t['millis'] as int,
          label: t['label'] as String,
          days: t['days'] as int,
          sound: t['sound'] as String?,
        );
      }
    }

    final fenceJson = jsonEncode(fences(clocks, s.list('items'), s.list('places')));
    if (fenceJson != _sentFences) {
      _sentFences = fenceJson;
      await Native.geofences(fenceJson);
    }
  }

  /// Alarms set by voice ("wake me at 6:30") join the Clock page as one-time alarms.
  static Future<void> drainVoiceAlarms(Store s) async {
    final added = await Native.takeNewClocks();
    for (final a in added) {
      final at = DateTime.fromMillisecondsSinceEpoch(a['at'] as int);
      if (s.byId('clocks', a['id'] as int) != null) continue;
      s.list('clocks').add({
        'id': a['id'],
        'label': '',
        'on': true,
        'time': '${two(at.hour)}:${two(at.minute)}',
        'days': <int>[],
        'at': a['at'],
      });
    }
    if (added.isNotEmpty) s.save();
  }

  /// One-time place alarms that went off are switched off here too.
  static Future<void> drainFired(Store s) async {
    for (final key in await Native.takeGeoFired()) {
      if (!key.startsWith('clock:')) continue;
      final c = s.byId('clocks', int.tryParse(key.substring(6)));
      if (c != null && c['on'] == true) {
        c['on'] = false;
        s.save();
      }
    }
  }
}
