import 'dart:convert';

/// One event or to-do read from a calendar file.
class IcsEvent {
  IcsEvent({
    required this.title,
    required this.start,
    this.allDay = false,
    this.minutes,
    this.repeat,
    this.approx = false,
    this.desc,
    this.tags = const [],
    this.uid,
    this.lead,
    this.todo = false,
  });
  final String title;
  final DateTime start;
  final bool allDay;

  /// Length in minutes, if the file said (end time or duration).
  final int? minutes;

  /// daily, weekly, monthly or yearly, when the file's rule is that simple.
  final String? repeat;

  /// The file repeats in a way Jarvis cannot (every 2 weeks, certain weekdays, a count): only the first one is kept.
  final bool approx;
  final String? desc;
  final List<String> tags;
  final String? uid;

  /// Minutes before the start that the file asked to be reminded.
  final int? lead;
  final bool todo;
}

/// Calendar files (.ics): write Jarvis's events and dated tasks, read other calendars. Pure Dart.
class Ics {
  // ---------- write ----------

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _utc(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}T${_two(d.hour)}${_two(d.minute)}${_two(d.second)}Z';
  }

  static String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}';

  static String escape(String t) =>
      t.replaceAll('\\', '\\\\').replaceAll(';', '\;').replaceAll(',', '\\,').replaceAll('\r\n', '\\n').replaceAll('\n', '\\n');

  static String unescape(String t) {
    final b = StringBuffer();
    for (var i = 0; i < t.length; i++) {
      if (t[i] == '\\' && i + 1 < t.length) {
        final n = t[++i];
        b.write(n == 'n' || n == 'N' ? '\n' : n);
      } else {
        b.write(t[i]);
      }
    }
    return b.toString();
  }

  /// Lines may be at most 75 bytes; longer ones continue on the next line after a space.
  static String fold(String line) {
    final out = StringBuffer();
    var bytes = 0;
    for (final r in line.runes) {
      final ch = String.fromCharCode(r);
      final n = utf8.encode(ch).length;
      if (bytes + n > 75) {
        out.write('\r\n ');
        bytes = 1;
      }
      out.write(ch);
      bytes += n;
    }
    return out.toString();
  }

  static const _freq = {'daily': 'DAILY', 'weekly': 'WEEKLY', 'monthly': 'MONTHLY', 'yearly': 'YEARLY'};

  /// Events become VEVENT, dated tasks become VTODO. Alarms, cancelled and undated items are left out.
  static String export(List<Map<String, dynamic>> items, {DateTime? now}) {
    final stamp = _utc((now ?? DateTime.now()).millisecondsSinceEpoch);
    final l = <String>['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Jarvis//Calendar//EN', 'CALSCALE:GREGORIAN'];
    for (final i in items) {
      final kind = i['kind'];
      final when = i['when'];
      if ((kind != 'event' && kind != 'task') || when is! int || i['status'] == 'cancelled') continue;
      final isEvent = kind == 'event';
      final allDay = i['allDay'] == true;
      final start = DateTime.fromMillisecondsSinceEpoch(when);
      l..add(isEvent ? 'BEGIN:VEVENT' : 'BEGIN:VTODO')
       ..add('UID:jarvis-${i['id']}@jarcis')
       ..add('DTSTAMP:$stamp')
       ..add('SUMMARY:${escape('${i['title']}')}');
      if (isEvent) {
        if (allDay) {
          l.add('DTSTART;VALUE=DATE:${_date(start)}');
          l.add('DTEND;VALUE=DATE:${_date(DateTime(start.year, start.month, start.day + 1))}');
        } else {
          l.add('DTSTART:${_utc(when)}');
          l.add('DTEND:${_utc(when + ((i['dur'] as int?) ?? 60) * 60000)}');
        }
      } else {
        l.add(allDay ? 'DUE;VALUE=DATE:${_date(start)}' : 'DUE:${_utc(when)}');
        if (i['status'] == 'done') l.add('STATUS:COMPLETED');
      }
      final desc = i['desc'];
      if (desc is String && desc.isNotEmpty) l.add('DESCRIPTION:${escape(desc)}');
      final tags = [for (final t in (i['tags'] as List? ?? const [])) escape('$t')];
      if (tags.isNotEmpty) l.add('CATEGORIES:${tags.join(',')}');
      final rule = _freq[i['repeat']];
      if (rule != null) l.add('RRULE:FREQ=$rule');
      final lead = (i['lead'] as num?)?.toInt() ?? 0;
      if (isEvent && !allDay && lead > 0) {
        l..add('BEGIN:VALARM')
         ..add('ACTION:DISPLAY')
         ..add('DESCRIPTION:${escape('${i['title']}')}')
         ..add('TRIGGER:-PT${lead}M')
         ..add('END:VALARM');
      }
      l.add(isEvent ? 'END:VEVENT' : 'END:VTODO');
    }
    l.add('END:VCALENDAR');
    return '${l.map(fold).join('\r\n')}\r\n';
  }

  // ---------- read ----------

  static List<String> _unfold(String text) {
    final lines = <String>[];
    for (final raw in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
      if (raw.isNotEmpty && (raw[0] == ' ' || raw[0] == '\t') && lines.isNotEmpty) {
        lines[lines.length - 1] += raw.substring(1);
      } else {
        lines.add(raw);
      }
    }
    return lines;
  }

  /// Splits "DTSTART;TZID=Asia/Dhaka:2026..." into name, parameters and value.
  static (String, Map<String, String>, String) _prop(String line) {
    // The first colon outside quotes ends the name and parameters.
    var q = false;
    var cut = -1;
    for (var i = 0; i < line.length; i++) {
      if (line[i] == '"') q = !q;
      if (line[i] == ':' && !q) {
        cut = i;
        break;
      }
    }
    if (cut < 0) return ('', {}, '');
    final head = line.substring(0, cut).split(';');
    final params = <String, String>{};
    for (final p in head.skip(1)) {
      final eq = p.indexOf('=');
      if (eq > 0) params[p.substring(0, eq).toUpperCase()] = p.substring(eq + 1).replaceAll('"', '');
    }
    return (head.first.toUpperCase(), params, line.substring(cut + 1));
  }

  /// A date or date-time. UTC (Z) becomes local time; times with no zone or a named zone are taken as local.
  static (DateTime, bool)? _when(String value, Map<String, String> params) {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$').firstMatch(value.trim());
    if (m == null) return null;
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    if (m[4] == null || params['VALUE'] == 'DATE') return (DateTime(y, mo, d), true);
    final h = int.parse(m[4]!), mi = int.parse(m[5]!), s = int.tryParse(m[6] ?? '0') ?? 0;
    return (m[7] == 'Z' ? DateTime.utc(y, mo, d, h, mi, s).toLocal() : DateTime(y, mo, d, h, mi, s), false);
  }

  /// "PT1H30M", "P1D", "P1W" → minutes. A leading "-" makes it negative.
  static int? duration(String v) {
    final m = RegExp(r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$').firstMatch(v.trim());
    if (m == null) return null;
    int n(int g) => int.tryParse(m[g] ?? '') ?? 0;
    final total = n(2) * 10080 + n(3) * 1440 + n(4) * 60 + n(5) + n(6) ~/ 60;
    return m[1] == '-' ? -total : total;
  }

  /// A rule Jarvis can repeat on its own, or whether the file's rule is more than that.
  static (String?, bool) rule(String v) {
    final parts = {
      for (final p in v.split(';'))
        if (p.contains('=')) p.substring(0, p.indexOf('=')).toUpperCase(): p.substring(p.indexOf('=') + 1).toUpperCase(),
    };
    final repeat = {'DAILY': 'daily', 'WEEKLY': 'weekly', 'MONTHLY': 'monthly', 'YEARLY': 'yearly'}[parts['FREQ']];
    final simple = parts.keys.every((k) => k == 'FREQ' || (k == 'INTERVAL' && parts[k] == '1'));
    return simple ? (repeat, false) : (null, true);
  }

  /// Events and to-dos in the file. Cancelled and completed ones, and ones with no usable start, are skipped.
  static List<IcsEvent> parse(String text) {
    final out = <IcsEvent>[];
    Map<String, (Map<String, String>, String)>? cur; // properties of the open VEVENT/VTODO
    var todo = false;
    var inAlarm = false;
    int? lead;
    for (final line in _unfold(text)) {
      if (line.isEmpty) continue;
      final (name, params, value) = _prop(line);
      if (name == 'BEGIN') {
        final v = value.toUpperCase();
        if (v == 'VEVENT' || v == 'VTODO') {
          cur = {};
          todo = v == 'VTODO';
          lead = null;
          inAlarm = false;
        } else if (v == 'VALARM' && cur != null) {
          inAlarm = true;
        }
        continue;
      }
      if (name == 'END') {
        final v = value.toUpperCase();
        if (v == 'VALARM') {
          inAlarm = false;
        } else if ((v == 'VEVENT' || v == 'VTODO') && cur != null) {
          final e = _build(cur, todo, lead);
          if (e != null) out.add(e);
          cur = null;
        }
        continue;
      }
      if (cur == null) continue;
      if (inAlarm) {
        if (name == 'TRIGGER' && params['RELATED'] != 'END') {
          final m = duration(value);
          if (m != null && m < 0) lead ??= -m;
        }
        continue;
      }
      cur.putIfAbsent(name, () => (params, value));
    }
    return out;
  }

  static IcsEvent? _build(Map<String, (Map<String, String>, String)> p, bool todo, int? lead) {
    final status = p['STATUS']?.$2.toUpperCase();
    if (status == 'CANCELLED' || status == 'COMPLETED') return null;
    final s = p[todo ? 'DUE' : 'DTSTART'] ?? p['DTSTART'];
    if (s == null) return null;
    final start = _when(s.$2, s.$1);
    if (start == null) return null;
    int? minutes;
    final end = p['DTEND'];
    final dur = p['DURATION'];
    if (end != null) {
      final e = _when(end.$2, end.$1);
      if (e != null && !start.$2) {
        final m = e.$1.difference(start.$1).inMinutes;
        if (m > 0) minutes = m;
      }
    } else if (dur != null) {
      final m = duration(dur.$2);
      if (m != null && m > 0 && !start.$2) minutes = m;
    }
    final (repeat, approx) = p['RRULE'] == null ? (null, false) : rule(p['RRULE']!.$2);
    final title = unescape(p['SUMMARY']?.$2 ?? '').trim();
    final desc = unescape(p['DESCRIPTION']?.$2 ?? '').trim();
    return IcsEvent(
      title: title.isEmpty ? '(No title)' : title,
      start: start.$1,
      allDay: start.$2,
      minutes: minutes,
      repeat: repeat,
      approx: approx,
      desc: desc.isEmpty ? null : desc,
      tags: [
        for (final t in (p['CATEGORIES']?.$2 ?? '').split(','))
          if (t.trim().isNotEmpty) unescape(t.trim()),
      ],
      uid: p['UID']?.$2.trim(),
      lead: lead,
      todo: todo,
    );
  }
}
