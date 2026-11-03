import 'dart:convert';

import 'gemini.dart';
import 'store.dart';

/// Turns captured text into tasks, alarms, habits, promises, decisions and journal entries.
class Brain {
  static bool _busy = false;

  static final _intent = RegExp(
    r'\b(\d{1,2}:\d{2}|\d{1,2}\s*(am|pm)|tomorrow|today|tonight|meeting|remind|alarm|deadline|appointment|call|send|email|buy|submit|finish|complete|need to|have to|must|should|will|going to|promise|decided|decide|plan|push|delay|move|cancel|postpone|did|went|ran|done|gym|read|study|workout|behind|late|schedule|task|todo)\b',
    caseSensitive: false,
  );

  /// Local pre-filter: small talk stays on the phone and is never sent to the AI.
  static bool looksLikeUpdate(String t) =>
      t.trim().split(RegExp(r'\s+')).length >= 3 && _intent.hasMatch(t);

  /// Saves a note first, so nothing is ever lost, then tries to process it.
  static Future<void> capture(Store s, String raw, {String source = 'in-app'}) async {
    final skip = s.settings['prefilter'] == true && !looksLikeUpdate(raw);
    s.list('captures').add({
      'id': s.nextId(),
      'ts': DateTime.now().millisecondsSinceEpoch,
      'raw': raw,
      'cleaned': raw,
      'status': skip ? 'skipped' : 'pending',
      'topics': <String>[],
      'msg': skip ? 'Kept on this phone and not sent to the AI.' : '',
      'actionId': null,
      'past': <String>[],
      'source': source,
    });
    s.save();
    if (!skip) await drain(s);
  }

  /// Processes waiting notes oldest first. Stops at the first failure and tries again later.
  static Future<void> drain(Store s) async {
    if (_busy) return;
    _busy = true;
    try {
      final waiting = s.list('captures').where((c) => c['status'] == 'pending').toList();
      for (final c in waiting) {
        if (!await _process(s, c)) break;
      }
    } finally {
      _busy = false;
    }
  }

  static String _stripFence(String t) {
    var x = t.trim();
    if (x.startsWith('```')) {
      x = x.replaceFirst(RegExp(r'^```[a-zA-Z]*'), '');
      if (x.endsWith('```')) x = x.substring(0, x.length - 3);
    }
    return x.trim();
  }

  static Future<bool> _process(Store s, Rec c) async {
    if (s.apiKey.isEmpty) {
      c['msg'] = 'Add your Gemini key in Settings. This note is saved and will be processed then.';
      s.save();
      return false;
    }
    String text;
    try {
      text = await Gemini.generate(s, _parserPrompt(s, c['raw'] as String), json: true);
    } catch (e) {
      c['msg'] = 'Waiting for the AI: $e';
      s.save();
      return false;
    }
    Rec data;
    try {
      data = jsonDecode(_stripFence(text)) as Rec;
    } catch (_) {
      c['status'] = 'failed';
      c['msg'] = 'Could not read the AI answer. Tap Retry.';
      s.save();
      return true;
    }

    final capId = c['id'] as int;
    final undo = <Rec>[];
    final msgs = <String>[];
    try {
      final topics = ((data['topics'] as List?) ?? []).map((e) => e.toString().toLowerCase()).toList();
      for (final raw in ((data['items'] as List?) ?? [])) {
        final p = Map<String, dynamic>.from(raw as Map);
        final type = (p['type'] ?? 'note').toString();
        if (type == 'ignore') continue;
        final why = reviewReason(s, p);
        if (why != null) {
          s.addInbox(p, capId, why, undo);
          msgs.add('Needs review: ${p['title'] ?? type} ($why)');
        } else {
          final m = await applyParsed(s, p, capId, topics, undo);
          if (m != null) msgs.add(m);
        }
      }

      final past = s.relatedDecisions(topics, capId).map((d) {
        final reason = d['reason'];
        return 'Past you decided: ${d['decision']}${reason == null ? '' : ' (because $reason)'}';
      }).toList();

      final cleaned = (data['cleaned'] as String?)?.trim() ?? '';
      c['cleaned'] = cleaned.isNotEmpty ? cleaned : c['raw'];
      c['topics'] = topics;
      c['past'] = past;
      c['actionId'] = msgs.isEmpty ? null : s.logAction(msgs.join('; '), undo);
      c['msg'] = msgs.isEmpty ? 'Saved to your journal.' : msgs.join('\n');
      c['status'] = 'done';
    } catch (e) {
      // Remove whatever was already created, so Retry starts clean instead of making duplicates.
      if (undo.isNotEmpty) await s.undo(s.logAction('Rolled back: ${c['raw']}', undo));
      c['actionId'] = null;
      c['status'] = 'failed';
      c['msg'] = 'Could not apply the AI answer ($e). Tap Retry.';
    }
    s.save();
    return true;
  }

  // ---------- review rules ----------

  static String? reviewReason(Store s, Rec p) {
    final type = p['type'];
    final conf = (p['confidence'] as num?)?.toDouble() ?? 0;
    if (conf < 0.7) return 'not sure I understood';
    final time = p['time'] as String?;
    final date = p['date'] as String?;
    if ((type == 'alarm' || type == 'event') && time == null) return 'no time given';
    if (type == 'delay') {
      if (time == null && date == null) return 'no new time given';
      if (findItem(s, p['target'] as String?) == null) return 'which item?';
    }
    if (type == 'habit_log' && findHabit(s, p['habit'] as String?) == null) {
      return 'no habit with that name';
    }
    if (type == 'promise' && date == null) return 'no deadline given';
    return null;
  }

  static Set<String> _words(String t) =>
      t.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.length > 2).toSet();

  static Rec? findItem(Store s, String? target) {
    if (target == null) return null;
    final tw = _words(target);
    Rec? best;
    var bestScore = 0;
    var tie = false;
    for (final it in s.list('items')) {
      if (it['status'] != 'open') continue;
      final score = _words(it['title'] as String).intersection(tw).length;
      if (score > bestScore) {
        best = it;
        bestScore = score;
        tie = false;
      } else if (score == bestScore && score > 0) {
        tie = true;
      }
    }
    return tie ? null : best;
  }

  static Rec? findHabit(Store s, String? name) {
    if (name == null) return null;
    final n = name.toLowerCase().trim();
    for (final h in s.list('habits')) {
      final hn = (h['name'] as String).toLowerCase();
      if (n.isNotEmpty && (hn.contains(n) || n.contains(hn))) return h;
    }
    return null;
  }

  /// Date 'YYYY-MM-DD' and time 'HH:MM' to milliseconds. A date alone means 9:00. A time alone means the next one.
  static int? whenFrom(String? date, String? time) {
    final now = DateTime.now();
    DateTime? d;
    if (date != null) {
      final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
      if (m != null) d = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    }
    var h = 9;
    var mi = 0;
    if (time != null) {
      final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time);
      if (m == null) return null;
      h = int.parse(m[1]!);
      mi = int.parse(m[2]!);
      if (h > 23 || mi > 59) return null;
    }
    if (d == null && time == null) return null;
    var t = d == null
        ? DateTime(now.year, now.month, now.day, h, mi)
        : DateTime(d.year, d.month, d.day, h, mi);
    if (d == null && !t.isAfter(now)) t = DateTime(now.year, now.month, now.day + 1, h, mi);
    return t.millisecondsSinceEpoch;
  }

  // ---------- applying parsed items ----------

  static Future<String?> applyParsed(
    Store s,
    Rec p,
    int capId,
    List<String> topics,
    List<Rec> undo,
  ) async {
    final type = p['type'].toString();
    final title = ((p['title'] as String?) ?? '').trim();
    final when = whenFrom(p['date'] as String?, p['time'] as String?);

    if (type == 'task' || type == 'event' || type == 'alarm') {
      final same = s.list('items').any((i) =>
          i['status'] == 'open' &&
          i['kind'] == type &&
          i['when'] == when &&
          (i['title'] as String).trim().toLowerCase() == title.toLowerCase());
      if (same) return 'Already have: $title';
    }

    if (type == 'task') {
      final est = (p['estimateMinutes'] as num?)?.toInt();
      final cat = p['category'] as String?;
      await s.addItem(kind: 'task', title: title, when: when, est: est, cat: cat, captureId: capId, undo: undo);
      final sug = s.estimateSuggestion(cat, est);
      final tail = sug == null
          ? ''
          : '. You usually take ${sug.ratio.toStringAsFixed(1)}x longer; try ${sug.est} min';
      return 'Task: $title${when == null ? '' : ' (${niceWhen(when)})'}$tail';
    }
    if (type == 'event' || type == 'alarm') {
      await s.addItem(kind: type, title: title, when: when, captureId: capId, undo: undo);
      return '${type == 'alarm' ? 'Alarm' : 'Event'}: $title${when == null ? '' : ' (${niceWhen(when)})'}';
    }
    if (type == 'delay') {
      final it = findItem(s, p['target'] as String?);
      if (it == null) return null;
      final old = it['when'] as int?;
      final base = old != null ? fromMs(old) : DateTime.now();
      final nw = whenFrom(
        (p['date'] as String?) ?? dayKey(base),
        (p['time'] as String?) ?? (old != null ? '${base.hour}:${two(base.minute)}' : null),
      );
      if (nw == null) return null;
      undo.add({'op': 'put', 'col': 'items', 'rec': copyRec(it)});
      it['when'] = nw;
      it['postponed'] = ((it['postponed'] as int?) ?? 0) + 1;
      it['nid'] ??= s.nextId();
      await s.syncRecord('items', it);
      return 'Moved ${it['title']} to ${niceWhen(nw)}';
    }
    if (type == 'habit_log') {
      final h = findHabit(s, p['habit'] as String?);
      if (h == null) return null;
      final day = (p['date'] as String?) ?? dayKey(DateTime.now());
      final before = s.streakWeeks(h);
      undo.add({'op': 'put', 'col': 'habits', 'rec': copyRec(h)});
      (h['logs'] as Rec)[day] = 'yes';
      final after = s.streakWeeks(h);
      if (after > before) await s.boost('${h['name']}: $after week streak');
      return 'Logged ${h['name']}';
    }
    if (type == 'promise') {
      final person = ((p['person'] as String?) ?? 'someone').trim();
      await s.addPromise(person: person, what: title, due: when, captureId: capId, undo: undo);
      return 'Promise to $person: $title';
    }
    if (type == 'decision') {
      s.addDecision(
        decision: title,
        reason: p['reason'] as String?,
        tags: topics,
        captureId: capId,
        undo: undo,
      );
      return 'Decision noted: $title';
    }
    return null;
  }

  /// Applies an item the user approved from the review inbox.
  static Future<void> acceptInbox(
    Store s,
    Rec entry, {
    String? date,
    String? time,
    String? target,
    String? habit,
  }) async {
    final p = Map<String, dynamic>.from(entry['item'] as Map);
    if (date != null) p['date'] = date;
    if (time != null) p['time'] = time;
    if (target != null) p['target'] = target;
    if (habit != null) p['habit'] = habit;
    final undo = <Rec>[
      {'op': 'put', 'col': 'inbox', 'rec': copyRec(entry)},
    ];
    final capId = entry['captureId'] as int;
    final cap = s.byId('captures', capId);
    final topics = ((cap?['topics'] as List?) ?? []).map((e) => e.toString()).toList();
    s.list('inbox').removeWhere((r) => r['id'] == entry['id']);
    final msg = await applyParsed(s, p, capId, topics, undo);
    s.logAction('Accepted: ${msg ?? p['title']}', undo);
    s.save();
  }

  static void discardInbox(Store s, Rec entry) {
    s.list('inbox').removeWhere((r) => r['id'] == entry['id']);
    s.logAction('Discarded: ${(entry['item'] as Map)['title']}', [
      {'op': 'put', 'col': 'inbox', 'rec': copyRec(entry)},
    ]);
    s.save();
  }

  // ---------- journal summary and questions ----------

  static Future<void> summarize(Store s, String day) async {
    final caps = s.capturesOn(day);
    if (caps.isEmpty) return;
    final notes = caps.map((c) => '${clock(c['ts'] as int)} ${c['cleaned']}').join('\n');
    final text = await Gemini.generate(
      s,
      'Write a short journal entry in first person, past tense, natural and warm, from these notes of one day. '
      'Use only what is in the notes. Do not add feelings, facts or advice.\nNotes:\n$notes',
      json: false,
    );
    s.summaries[day] = text.trim();
    s.save();
  }

  static Future<String> ask(Store s, String question) async {
    final q = _words(question);
    final scored = <MapEntry<Rec, int>>[];
    for (final c in s.list('captures')) {
      if (c['status'] != 'done') continue;
      final score = _words(c['cleaned'].toString()).intersection(q).length;
      if (score > 0) scored.add(MapEntry(c, score));
    }
    if (scored.isEmpty) return 'I found nothing in your journal about that.';
    scored.sort((a, b) => b.value.compareTo(a.value));
    final notes = scored.take(15).map((e) {
      final c = e.key;
      return '${dayKey(fromMs(c['ts'] as int))}: ${c['cleaned']}';
    }).join('\n');
    return (await Gemini.generate(
      s,
      'Answer the question using only these journal entries. Mention dates. '
      'If the entries do not answer it, say so.\nEntries:\n$notes\nQuestion: $question',
      json: false,
    )).trim();
  }

  // ---------- prompt ----------

  static String _parserPrompt(Store s, String note) {
    final now = DateTime.now();
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final open = s.list('items').where((i) => i['status'] == 'open').map((i) => '"${i['title']}"').join(', ');
    final habits = s.list('habits').map((h) => '"${h['name']}"').join(', ');
    return '''You turn a person's spoken notes into structured data. Today is ${days[now.weekday - 1]} ${dayKey(now)}, local time ${two(now.hour)}:${two(now.minute)}.
Open items the person already has (use these for delays): ${open.isEmpty ? 'none' : open}
Habits the person tracks: ${habits.isEmpty ? 'none' : habits}

Return ONLY JSON in this shape:
{"cleaned": string, "topics": [string], "items": [ {"type": string, "title": string, "date": string or null, "time": string or null, "target": string or null, "person": string or null, "reason": string or null, "habit": string or null, "estimateMinutes": integer or null, "category": string or null, "confidence": number} ]}

"cleaned": the note with grammar fixed, same meaning, first person, nothing added.
"topics": 1 to 4 lowercase single words about what the note covers.
"type" is one of: task, event, alarm, delay, habit_log, promise, decision, note, ignore.
"date" is YYYY-MM-DD and "time" is HH:MM in 24 hours, both local. For a promise, "date" is the deadline.
"target" is, for a delay, the title of the existing open item it refers to. "habit" is, for habit_log, the tracked habit name. "person" is, for a promise, who it was made to. "reason" is, for a decision, why the person decided.
"category" is one lowercase word for the kind of work, such as report, email, call, errand.
"confidence" is 0 to 1.

Rules:
- Never invent a date or time that was not said. If it is unclear ("later", "soon"), set time to null and lower the confidence.
- A meeting or appointment at a time is "event". Use "alarm" only when the person asks to be woken or reminded at a time.
- A promise is a commitment made to another person. A decision is a choice the person made.
- "delay" moves an existing item; give the new date or time.
- Small talk, or anything that is not about plans, tasks, habits, promises, decisions or reflections, is type "ignore".
- One note can hold several items, but one real-world thing is ONE item. A class or appointment at a time is one "event" (it already gets a reminder); do not also add a task or alarm for it unless the person separately asks to be woken or reminded.
- If the note is about something already in the open items list, do not create it again: use "delay" if its time changed, otherwise "ignore".
- Never output two items with the same title and time.
- If the same thing happens on several dates, output one item per date.
- Notes may be in English, Bengali, or Bengali written in English letters (for example "kal" = tomorrow, "porshu" = day after tomorrow, "tarikh" = date, "tar por" = after that, "sondhay" = evening, "sokal" = morning). Understand them. Write "title" in short plain English; keep "cleaned" in the language the person used.

Note: """$note"""''';
  }
}
