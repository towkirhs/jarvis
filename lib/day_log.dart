import 'store.dart';

/// One thing you said you are doing ("started gym", "back home", "now: reading").
class NowAct {
  const NowAct(this.verb, this.what);

  /// start, finish, back, wake or sleep.
  final String verb;
  final String what;

  String get text => switch (verb) {
        'finish' => 'Finished $what',
        'back' => what.isEmpty ? 'Back' : 'Back $what',
        'wake' => 'Woke up',
        'sleep' => 'Going to sleep',
        _ => 'Started $what',
      };
}

/// The day as it really went: what you said you did, what you answered at the end of planned blocks,
/// tasks you finished, and time in apps.
class NowLog {
  static final _start = RegExp(r"^(?:i\s*'?\s*(?:am|m)\s+|i\s+|just\s+)*(?:started|starting|start|began|beginning|doing|now doing)\s+(?:to\s+|with\s+|on\s+)?(.+)$");
  static final _finish = RegExp(r'^(?:i\s+|just\s+)*(?:finished|done with|completed|stopped|ended)\s+(.+)$');
  static final _back = RegExp(r"^(?:i\s*'?\s*(?:am|m)\s+|just\s+)*back(?:\s+(home|(?:at|from|to|in)\s+.+))?$");
  static final _wake = RegExp(r"^(?:i\s+|just\s+)*(?:woke up|got up|am up|i'm up|up now)$");
  static final _sleep = RegExp(r'^(?:going to (?:sleep|bed)|off to bed|good ?night|sleeping now)$');

  /// A time or date in the note means it is a plan ("start gym at 6", "finish the report tomorrow"), not a log.
  static final _plan = RegExp(
      r"\b(?:\d{1,2}\s*(?:am|pm)|\d{1,2}:\d{2}|at \d|tomorrow|tonight|later|next|every|remind|o'clock|by \w+day|on (?:mon|tue|wed|thu|fri|sat|sun)\w*|in \d+ (?:min|hour|day))");

  /// What [raw] logs, or null if it is not a "what I am doing now" note. [forced]: it came with "now:".
  static NowAct? parse(String raw, {bool forced = false}) {
    final t = raw.trim().toLowerCase().replaceAll(RegExp(r'[.!]+$'), '').replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return null;
    if (!forced && (t.split(' ').length > 7 || _plan.hasMatch(t))) return null;
    String keep(String part) {
      // Keep the words as written (only the match was lower-cased).
      final i = t.lastIndexOf(part);
      final original = raw.trim().replaceAll(RegExp(r'[.!]+$'), '').replaceAll(RegExp(r'\s+'), ' ');
      return i >= 0 && original.length == t.length ? original.substring(i, i + part.length) : part;
    }

    if (_wake.hasMatch(t)) return const NowAct('wake', '');
    if (_sleep.hasMatch(t)) return const NowAct('sleep', '');
    var m = _back.firstMatch(t);
    if (m != null) return NowAct('back', m[1] == null ? '' : keep(m[1]!));
    m = _finish.firstMatch(t);
    if (m != null) return NowAct('finish', keep(m[1]!));
    m = _start.firstMatch(t);
    if (m != null) return NowAct('start', keep(m[1]!));
    return forced ? NowAct('start', raw.trim()) : null;
  }

  /// The open task [what] most likely means (its title contains the words, or they contain the title).
  static Rec? task(List<Rec> items, String what) {
    final w = what.toLowerCase().replaceAll(RegExp(r'^(the|my|a)\s+'), '').trim();
    if (w.length < 3) return null;
    final open = items.where((i) => i['kind'] == 'task' && i['status'] == 'open' && i['title'] is String).toList();
    for (final i in open) {
      if ((i['title'] as String).toLowerCase() == w) return i;
    }
    for (final i in open) {
      final title = (i['title'] as String).toLowerCase();
      if (title.length >= 3 && (title.contains(w) || w.contains(title))) return i;
    }
    return null;
  }
}

/// A question at the end of a planned block: "Finished Study?"
class CheckIn {
  /// Notification ids for check-ins start here, clear of items, snoozes and early reminders.
  static const idBase = 1400000000;
  static int id(int nid) => idBase + nid;

  /// When [item]'s check-in is due: the end of its planned block, or null if it has none.
  static int? at(Rec item) {
    final when = item['when'];
    if (item['kind'] != 'task' || item['status'] != 'open' || item['planned'] == null || item['allDay'] == true || when is! int) {
      return null;
    }
    return when + ((item['est'] as int?) ?? 30) * 60000;
  }

  /// What a typed answer means: skipping it, or what you did instead.
  static bool isSkip(String? text) {
    final t = (text ?? '').trim().toLowerCase().replaceAll(RegExp(r'[.!]+$'), '');
    return t.isEmpty || RegExp(r"^(skip|skipped|no|nope|didn't|did not|not done|nothing|cancel)$").hasMatch(t);
  }
}

/// A stretch of time in one app.
class AppSession {
  const AppSession(this.pkg, this.name, this.start, this.end);
  final String pkg;
  final String name;
  final DateTime start;
  final DateTime end;

  int get minutes => end.difference(start).inMinutes;

  static AppSession? from(Map m) {
    final s = m['start'], e = m['end'];
    if (s is! int || e is! int || e <= s) return null;
    return AppSession('${m['pkg']}', '${m['name'] ?? m['pkg']}', DateTime.fromMillisecondsSinceEpoch(s), DateTime.fromMillisecondsSinceEpoch(e));
  }

  /// Back-to-back stretches in the same app (gaps under [gap]) joined into one.
  static List<AppSession> merge(List<AppSession> all, {Duration gap = const Duration(minutes: 2)}) {
    final sorted = [...all]..sort((a, b) => a.start.compareTo(b.start));
    final out = <AppSession>[];
    for (final s in sorted) {
      final last = out.isEmpty ? null : out.last;
      if (last != null && last.pkg == s.pkg && s.start.difference(last.end) <= gap) {
        out[out.length - 1] = AppSession(last.pkg, last.name, last.start, s.end.isAfter(last.end) ? s.end : last.end);
      } else {
        out.add(s);
      }
    }
    return out;
  }

  /// Minutes per app, most used first.
  static List<({String pkg, String name, int minutes})> totals(List<AppSession> all) {
    final ms = <String, int>{}, names = <String, String>{};
    for (final s in all) {
      ms[s.pkg] = (ms[s.pkg] ?? 0) + s.end.difference(s.start).inMilliseconds;
      names[s.pkg] = s.name;
    }
    final out = [for (final e in ms.entries) (pkg: e.key, name: names[e.key]!, minutes: e.value ~/ 60000)]
      ..removeWhere((t) => t.minutes < 1)
      ..sort((a, b) => b.minutes.compareTo(a.minutes));
    return out;
  }
}

/// One line of the day's timeline.
class Moment {
  const Moment(this.at, this.text, this.kind, {this.end});
  final DateTime at;
  final DateTime? end;
  final String text;

  /// now, wake, sleep, back, finish, done, skip, other, app, apps (a day's app summary).
  final String kind;
}

class DayLog {
  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// [day]'s timeline, oldest first: your log, finished tasks and app stretches of 5 minutes or more.
  static List<Moment> timeline(DateTime day, {required List<Rec> log, required List<Rec> items, List<AppSession> apps = const []}) {
    final out = <Moment>[];
    final entries = log.where((e) => e['at'] is int && _sameDay(DateTime.fromMillisecondsSinceEpoch(e['at'] as int), day)).toList()
      ..sort((a, b) => (a['at'] as int).compareTo(b['at'] as int));
    final saidDone = <Object?>{};
    for (var k = 0; k < entries.length; k++) {
      final e = entries[k];
      final at = DateTime.fromMillisecondsSinceEpoch(e['at'] as int);
      final verb = '${e['verb']}';
      if (e['kind'] == 'apps') {
        out.add(Moment(at, '${e['text']}', 'apps'));
        continue;
      }
      if (e['kind'] == 'check') {
        if (verb == 'done') saidDone.add(e['item']);
        final from = e['from'] is int ? DateTime.fromMillisecondsSinceEpoch(e['from'] as int) : null;
        out.add(Moment(from ?? at, '${e['text']}', verb, end: from == null ? null : at));
        continue;
      }
      if (verb == 'finish' && e['item'] != null) saidDone.add(e['item']);
      // Something you started runs until the next thing you said.
      DateTime? end;
      if (verb == 'start' || verb == 'back') {
        for (final n in entries.skip(k + 1)) {
          if (n['kind'] == 'now') {
            end = DateTime.fromMillisecondsSinceEpoch(n['at'] as int);
            break;
          }
        }
      }
      out.add(Moment(at, '${e['text']}', verb == 'start' ? 'now' : verb, end: end));
    }
    for (final i in items) {
      final at = i['doneAt'];
      if (i['status'] != 'done' || at is! int || saidDone.contains(i['id'])) continue;
      final d = DateTime.fromMillisecondsSinceEpoch(at);
      if (_sameDay(d, day)) out.add(Moment(d, 'Done: ${i['title']}', 'done'));
    }
    for (final s in AppSession.merge(apps)) {
      if (s.minutes >= 5 && _sameDay(s.start, day)) out.add(Moment(s.start, s.name, 'app', end: s.end));
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  static String span(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    return h == 0 ? '$m min' : (m == 0 ? '${h}h' : '${h}h ${m}m');
  }
}

/// How today's plan compares with what happened.
class PlanCheck {
  const PlanCheck({this.planned = 0, this.done = 0, this.skipped = 0, this.toCome = 0, this.late = const [], this.behind = 0});
  final int planned, done, skipped, toCome;

  /// Planned blocks that have ended and are still open, unanswered.
  final List<Rec> late;

  /// Minutes of planned work that should be done by now and is not.
  final int behind;

  static PlanCheck of(List<Rec> items, DateTime now, String dayKey) {
    var planned = 0, done = 0, skipped = 0, toCome = 0, behind = 0;
    final late = <Rec>[];
    for (final i in items) {
      if (i['kind'] != 'task' || i['allDay'] == true || i['when'] is! int) continue;
      if (i['planned'] != dayKey) {
        // Skipped at its check-in and not planned again today.
        if (i['skipped'] == dayKey) {
          planned++;
          skipped++;
        }
        continue;
      }
      planned++;
      if (i['status'] == 'done') {
        done++;
      } else if (i['status'] == 'open') {
        final est = (i['est'] as int?) ?? 30;
        if ((i['when'] as int) + est * 60000 <= now.millisecondsSinceEpoch) {
          late.add(i);
          behind += est;
        } else {
          toCome++;
        }
      }
    }
    return PlanCheck(planned: planned, done: done, skipped: skipped, toCome: toCome, late: late, behind: behind);
  }

  /// One line: on track, or how far behind.
  String get summary {
    if (planned == 0) return 'Nothing planned today';
    if (late.isNotEmpty) return 'Behind by ${DayLog.span(behind)}: ${late.length} block${late.length == 1 ? '' : 's'} not done';
    return 'On track: $done of $planned done${skipped == 0 ? '' : ', $skipped skipped'}';
  }
}

/// An alarm about an app: when you open it, or after a time in it.
class AppAlarm {
  /// open, today (total today over [min]), or sitting (one go over [min]).
  static const whens = ['open', 'today', 'sitting'];

  static String describe(Rec a) {
    final app = '${a['name'] ?? a['pkg']}';
    final min = (a['min'] as int?) ?? 60;
    return switch (a['when']) {
      'today' => '$app over ${DayLog.span(min)} today',
      'sitting' => '$app for ${DayLog.span(min)} in one go',
      _ => 'When I open $app',
    };
  }

  /// What the phone needs: the alarms that are on.
  static List<Map<String, dynamic>> forPhone(List<Rec> all) => [
        for (final a in all)
          if (a['on'] != false && a['pkg'] is String)
            {
              'id': a['id'],
              'pkg': a['pkg'],
              'when': a['when'] ?? 'open',
              'min': a['min'] ?? 60,
              'ring': a['ring'] == true,
              'text': (a['text'] as String?)?.trim().isNotEmpty == true ? a['text'] : describe(a),
            },
      ];
}
