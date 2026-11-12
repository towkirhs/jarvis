import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'cal_edit.dart';
import 'store.dart';

/// One thing the mirror has to do to keep Jarvis and the phone's calendar the same.
class MirrorOp {
  const MirrorOp(this.kind, {this.item, this.ev});

  /// create, update (Jarvis to the phone), pull (the phone to Jarvis), forget (the phone one was deleted)
  /// or remove (the Jarvis one is gone).
  final String kind;
  final Rec? item;
  final int? ev;

  @override
  String toString() => '$kind ${item?['id'] ?? ev}';
}

/// The rules for mirroring Jarvis events into a phone calendar and back. Pure Dart, tested on its own.
///
/// Each mirrored event has a link, kept on this phone only: {ev, jsig, psig}. The signatures are of what each
/// side looked like when they were last the same, so a change on either side is seen as a difference from them.
/// If both sides changed, Jarvis wins.
class CalMirror {
  /// What goes to the phone: events with a time. Not tasks or alarms, habit blocks, or events that came from the phone.
  static bool eligible(Rec i) =>
      i['kind'] == 'event' && i['status'] != 'cancelled' && i['when'] is int && i['habitId'] == null && i['ext'] == null;

  static int fnv(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  static int _utcDay(DateTime d, [int plus = 0]) => DateTime.utc(d.year, d.month, d.day + plus).millisecondsSinceEpoch;

  /// An item as the phone keeps it. All-day items run from one UTC midnight to the next after their last day.
  static Map<String, dynamic> toPhone(Rec item) {
    final when = fromMs(item['when'] as int);
    final allDay = item['allDay'] == true;
    final span = allDay ? ((item['span'] as num?)?.toInt() ?? 1) : 1;
    final start = allDay ? _utcDay(when) : when.millisecondsSinceEpoch;
    final end = allDay ? _utcDay(when, span) : start + CalEdit.minutes(item) * 60000;
    final repeat = item['repeat'] as String?;
    return {
      'title': item['title'],
      'start': start,
      'end': end,
      'allDay': allDay,
      'location': item['location'],
      'desc': item['desc'],
      'repeat': repeat,
      'skip': [
        if (repeat != null && !allDay)
          for (final k in (item['skip'] as List?) ?? const [])
            DateTime(int.parse('$k'.substring(0, 4)), int.parse('$k'.substring(5, 7)), int.parse('$k'.substring(8, 10)), when.hour, when.minute)
                .millisecondsSinceEpoch,
      ],
    };
  }

  /// What Jarvis looked like: a number that changes when anything the phone shows changes.
  static int signature(Rec item) {
    final p = toPhone(item);
    return fnv('${p['title']}|${p['start']}|${p['end']}|${p['allDay']}|${p['location'] ?? ''}|${p['desc'] ?? ''}|${p['repeat']}|${p['skip']}');
  }

  /// What the phone event looked like. Repeat rules are left out: Jarvis does not read them back.
  static int phoneSig(Map<String, dynamic> ev) =>
      fnv('${ev['title']}|${ev['start']}|${ev['end']}|${ev['allDay']}|${ev['location'] ?? ''}|${ev['desc'] ?? ''}');

  /// A phone event as Jarvis fields.
  static Rec fromPhone(Map<String, dynamic> ev) {
    final start = ev['start'] as int;
    final end = ev['end'] as int;
    if (ev['allDay'] == true) {
      final u = DateTime.fromMillisecondsSinceEpoch(start, isUtc: true);
      final days = ((end - start) / 86400000).round();
      return {
        'title': ev['title'],
        'when': DateTime(u.year, u.month, u.day).millisecondsSinceEpoch,
        'allDay': true,
        'dur': null,
        'span': days > 1 ? days : null,
        'location': ev['location'],
        'desc': ev['desc'],
      };
    }
    final mins = ((end - start) / 60000).round();
    return {
      'title': ev['title'],
      'when': start,
      'allDay': false,
      'dur': mins < 15 ? 15 : mins,
      'span': null,
      'location': ev['location'],
      'desc': ev['desc'],
    };
  }

  /// A phone event shown in Jarvis' calendar. It is not stored: it lives only in memory, and has a negative id.
  static Rec external(Map<String, dynamic> ev) {
    final f = fromPhone(ev);
    return {
      'id': -(1000000 + fnv('${ev['ev']}@${ev['start']}') % 1000000000),
      'kind': 'event',
      'status': 'open',
      'repeat': null,
      'tags': <String>[],
      'list': 'Calendar',
      'lead': 0,
      ...f,
      'ext': {'ev': ev['ev'], 'cal': ev['cal']},
      'extColor': ev['color'],
    };
  }

  /// What to do now. [links] are this phone's links by Jarvis id; [phone] holds the phone events that exist,
  /// by id, for the linked ones. [canWrite] is whether a calendar to write to has been chosen.
  static List<MirrorOp> plan({
    required List<Rec> items,
    required Map<String, dynamic> links,
    required Map<int, Map<String, dynamic>> phone,
    required bool canWrite,
  }) {
    final ops = <MirrorOp>[];
    final seen = <String>{};
    for (final it in items) {
      final key = '${it['id']}';
      final link = links[key] as Map?;
      if (!eligible(it)) continue;
      seen.add(key);
      if (link == null) {
        if (canWrite) ops.add(MirrorOp('create', item: it));
        continue;
      }
      if (link['off'] == true) continue;
      final pe = phone[link['ev'] as int];
      if (pe == null) {
        ops.add(MirrorOp('forget', item: it));
      } else if (signature(it) != link['jsig']) {
        ops.add(MirrorOp('update', item: it, ev: link['ev'] as int));
      } else if (phoneSig(pe) != link['psig']) {
        ops.add(MirrorOp('pull', item: it, ev: link['ev'] as int));
      }
    }
    for (final e in links.entries) {
      final l = e.value as Map;
      if (seen.contains(e.key) || l['off'] == true || l['ev'] == null) continue;
      ops.add(MirrorOp('remove', ev: l['ev'] as int));
    }
    return ops;
  }
}

/// The phone's calendar, through the Android side. Does nothing on the web.
class PhoneCalendarApi {
  static const _ch = MethodChannel('jarcis/native');

  static Future<bool> access() async => !kIsWeb && (await _ch.invokeMethod<bool>('calendarAccess') ?? false);

  static Future<void> request() async {
    if (!kIsWeb) await _ch.invokeMethod('requestCalendar');
  }

  /// [{id, name, account, color, writable}]
  static Future<List<Map<String, dynamic>>> calendars() async {
    if (kIsWeb) return [];
    final raw = await _ch.invokeMethod<String>('calendars');
    return raw == null ? [] : (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> instances(DateTime from, DateTime to, List<int> ids) async {
    if (kIsWeb || ids.isEmpty) return [];
    final raw = await _ch.invokeMethod<String>('calendarInstances', {
      'from': from.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
      'ids': ids,
    });
    return raw == null ? [] : (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  static Future<int> insert(int cal, Map<String, dynamic> ev) async =>
      await _ch.invokeMethod<int>('calendarInsert', {'cal': cal, 'json': jsonEncode(ev)}) ?? -1;

  static Future<bool> update(int ev, Map<String, dynamic> fields) async =>
      await _ch.invokeMethod<bool>('calendarUpdate', {'ev': ev, 'json': jsonEncode(fields)}) ?? false;

  static Future<bool> delete(int ev) async => await _ch.invokeMethod<bool>('calendarDelete', {'ev': ev}) ?? false;

  /// The event as it is now, or null if it is gone.
  static Future<Map<String, dynamic>?> event(int ev) async {
    final raw = await _ch.invokeMethod<String>('calendarEvent', {'ev': ev});
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> open(int ev) async {
    if (!kIsWeb) await _ch.invokeMethod('calendarOpen', {'ev': ev});
  }
}
