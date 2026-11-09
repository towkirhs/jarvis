import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'ai.dart';
import 'chatgpt_block.dart';
import 'clash.dart';
import 'decide.dart';
import 'destination.dart';
import 'habit_core.dart';
import 'local_parser.dart';
import 'memory.dart';
import 'native.dart';
import 'quick_answers.dart';
import 'store.dart';
import 'web.dart';

/// Turns captured text into tasks, alarms, habits, promises, decisions and journal entries.
class Brain {
  static bool _busy = false;

  static final _intent = RegExp(
    r'\b(\d{1,2}:\d{2}|\d{1,2}\s*(am|pm)|tomorrow|today|tonight|meeting|remind|alarm|deadline|appointment|call|send|email|buy|submit|finish|complete|need to|have to|must|should|will|going to|promise|decided|decide|plan|push|delay|move|cancel|postpone|did|went|ran|done|gym|read|study|workout|behind|late|schedule|task|todo|spent|spend|paid|pay|bought|cost|taka|tk|salary|income|received|got|transfer|bkash|nagad|expense|birthday|exam|what|when|how|which|where|show|finished|cancel|balance|left|feel|feeling|mood)\b',
    caseSensitive: false,
  );

  /// Local pre-filter: small talk stays on the phone and is never sent to the AI.
  static bool looksLikeUpdate(String t) =>
      t.trim().split(RegExp(r'\s+')).length >= 3 && _intent.hasMatch(t);

  /// Saves a note first, so nothing is ever lost, then tries to process it.
  /// [image] is the path of a photo to read along with the note.
  static Future<void> capture(Store s, String raw, {String source = 'in-app', String? image}) async {
    // Notes sent on purpose (the bubble, share, screenshots) are always processed; the filter is for typing here.
    final skip = image == null &&
        (source == 'in-app' || source == 'journal') &&
        !ChatGptBlock.has(raw) &&
        s.settings['prefilter'] == true &&
        !looksLikeUpdate(raw) &&
        Web.asked(raw) == null;
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
      'image': image,
      if (source.startsWith('reply')) 'replyTo': _replyContext(s, source),
    });
    s.save();
    if (!skip) await drain(s);
  }

  /// What an answer from a notification is answering: a reminder ("reply:123") or Jarvis's last message.
  static String? _replyContext(Store s, String source) {
    final id = int.tryParse(source.split(':').last);
    if (id == 1) return 'the morning check-in: "What is the one thing that matters today?"';
    if (id == 2) return 'the evening check-in: "How did today go?" (habits done, money spent, feelings all count)';
    if (id != null) {
      final it = s.byId('items', id);
      if (it != null) return 'the reminder for #$id "${it['title']}"';
      final p = s.byId('promises', id);
      if (p != null) return 'the reminder for promise #$id to ${p['person']}: "${p['what']}"';
    }
    final said = s.local('last_said');
    return said == null ? null : 'Jarvis, who had just said: "$said"';
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
    final ok = await _understand(s, c);
    // Notes sent from outside the app get Jarvis's answer back as a notification you can answer again.
    final reply = c['reply'] as String?;
    final outside = !const {'in-app', 'journal'}.contains(c['source']);
    // Typed in the app: spoken only if Voice replies is set to Always.
    if (ok && c['status'] == 'done' && !outside && reply != null) await Native.speak(reply);
    if (ok && c['status'] == 'done' && outside) {
      final said = reply ?? (c['msg'] as String? ?? '');
      await s.setLocal('last_said', said);
      await Native.notify('Jarvis', said, spoken: c['source'] == 'voice');
    } else if (!ok && outside && (c['source'] as String).startsWith('reply') && c['told'] != true) {
      // Answered from a notification: say once why nothing happened yet, instead of leaving "…" hanging.
      c['told'] = true;
      s.save();
      await Native.notify('Jarvis', !AI.available(s)
          ? "I need an AI set up (Settings, AI models) for that one. It's saved and I'll do it once the key is in."
          : "I can't reach the AI right now. Your answer is saved and I'll handle it when I can.");
    }
    return ok;
  }

  /// Everyday questions answered from your own data, without the AI.
  static String? _quickAnswer(Store s, String raw) => !AI.phoneOn(s)
      ? null
      : QuickAnswers.answer(
          raw,
          now: DateTime.now(),
          items: s.list('items'),
          tx: s.list('tx'),
          balances: {for (final a in s.list('accounts')) a['name'] as String: s.balance(a)},
          money: s.money,
        );

  static Future<bool> _understand(Store s, Rec c) async {
    // A "JARVIS v1" block from ChatGPT: already understood, so it is applied as written.
    if (c['image'] == null && ChatGptBlock.has(c['raw'] as String)) {
      c['via'] = 'ChatGPT';
      try {
        return await _apply(s, c, ChatGptBlock.parse(c['raw'] as String)!);
      } on FormatException catch (e) {
        return _apply(s, c, {'items': <dynamic>[], 'reply': 'I could not read that ChatGPT block: ${e.message}.'});
      }
    }
    // "done" / "cancel it" answering a reminder: act on that item straight away.
    final about = int.tryParse(((c['source'] as String?) ?? '').split(':').last);
    if (about != null) {
      final t = (c['raw'] as String).trim().toLowerCase().replaceAll(RegExp(r'[.!]+$'), '');
      final type = RegExp(r"^(ok(ay)? )?(done|did it|finished|completed|yes,? done|it's done|already done)$").hasMatch(t)
          ? 'complete'
          : RegExp(r"^(cancel( it)?|skip( it)?|not needed|no longer needed|forget it)$").hasMatch(t)
              ? 'cancel'
              : null;
      if (type != null && findTarget(s, '#$about') != null) {
        c['via'] = 'phone';
        return _apply(s, c, {
          'items': [
            {'type': type, 'target': '#$about', 'confidence': 1},
          ],
        });
      }
    }
    // "calendar: …", "task: …", "journal: …", "… to my calendar": you said where it goes, so it goes there.
    final dest = Destination.of(c['raw'] as String);
    final note = dest?.rest ?? c['raw'] as String;
    if (dest?.type == 'note') {
      c['via'] = 'phone';
      return _apply(s, c, {'items': <dynamic>[], 'cleaned': note});
    }
    // Your rule: only notes that start with "calendar" go on the calendar; anything else with a time is a task.
    // (A photo of a routine or exam schedule still makes events.)
    Rec forced(Rec data) =>
        dest != null ? Destination.force(data, dest) : (c['image'] == null ? Destination.noEvents(data) : data);
    // "calendar 3pm to 5pm team meeting": read on the phone, exactly as said.
    if (dest?.type == 'event' && c['image'] == null) {
      final cal = LocalParser.calendar(note, now: DateTime.now());
      if (cal != null) {
        c['via'] = 'phone';
        return _apply(s, c, cal);
      }
    }
    String? quick;
    try {
      quick = c['image'] == null && dest == null ? _quickAnswer(s, c['raw'] as String) : null;
    } catch (_) {
      // Odd data must never block the note: let the parser or the AI take it.
    }
    if (quick != null) {
      c['via'] = 'phone';
      return _apply(s, c, {'items': <dynamic>[], 'reply': quick});
    }
    // "search for X", "google X": straight to the web.
    final webQ = c['image'] == null && dest == null ? Web.asked(c['raw'] as String) : null;
    if (webQ != null) {
      if (!Web.available(s)) {
        c['via'] = 'phone';
        return _apply(s, c, {'items': <dynamic>[], 'reply': 'To search the web, add your Gemini key or a Groq API in Settings, AI models.'});
      }
      try {
        final a = await Web.search(s, webQ);
        c['via'] = AI.lastUsed;
        return await _apply(s, c, {'items': <dynamic>[], 'reply': a.text, 'sources': [for (final x in a.sources) x.toJson()]});
      } catch (e) {
        c['msg'] = 'Waiting to search the web: $e';
        s.save();
        return false;
      }
    }
    // "Should I…?", "X or Y?": a decision with odds, not a conversation.
    if (c['image'] == null && dest == null && AI.available(s) && Decide.isDecisionRequest(c['raw'] as String)) {
      try {
        final answers = await decide(s, c['raw'] as String, captureId: c['id'] as int);
        c['via'] = 'ai';
        c['decision'] = [for (final a in answers) a.toJson()];
        return await _apply(s, c, {'items': <dynamic>[], 'reply': verdict(s, answers.first)});
      } catch (e) {
        c['msg'] = 'Waiting for the AI: $e';
        s.save();
        return false;
      }
    }
    // Simple notes (alarms, timed tasks, money, habits, birthdays) are understood on the phone: no AI call.
    var local = c['image'] == null && AI.phoneOn(s)
        ? LocalParser.parse(
            note,
            now: DateTime.now(),
            habits: s.list('habits').map((h) => h['name'] as String).toList(),
            accounts: s.list('accounts').map((a) => a['name'] as String).toList(),
          )
        : null;
    // "done X" only counts when X is clearly one open item; otherwise the AI looks at it.
    final finished = local == null ? null : ((local['items'] as List).first as Map);
    if (finished != null && finished['type'] == 'complete' && findTarget(s, finished['target'] as String?) == null) {
      local = null;
    }
    // Phone rules first if they are first in your AI order (or there is no AI); otherwise they are the fallback.
    if (local != null && (AI.phoneFirst(s) || !AI.available(s))) {
      c['via'] = 'phone';
      return _apply(s, c, forced(local));
    }
    if (!AI.available(s) && dest != null) {
      c['via'] = 'phone';
      return _apply(s, c, forced({'items': <dynamic>[]}));
    }
    if (!AI.available(s)) {
      c['msg'] = 'No AI is set up (Settings, AI models). This note is saved and will be processed then.';
      s.save();
      return false;
    }
    String text;
    try {
      Uint8List? bytes;
      final path = c['image'] as String?;
      if (path != null) {
        try {
          bytes = await XFile(path).readAsBytes();
        } catch (_) {
          // The photo is gone (cleared from cache); go on with the text.
        }
      }
      text = await AI.generate(
        s,
        _parserPrompt(s, note,
            photo: bytes != null,
            replyTo: c['replyTo'] as String?,
            web: dest == null && Web.on(s) && Web.available(s),
            events: dest != null || bytes != null,
            dest: dest?.type),
        json: true,
        image: bytes,
        mime: path != null && path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg',
      );
    } catch (e) {
      if (local != null) {
        // Every AI failed, but the phone understood it: use that rather than wait.
        c['via'] = 'phone';
        return _apply(s, c, forced(local));
      }
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
    c['via'] = AI.lastUsed ?? 'ai';
    // The AI says the answer is on the internet: search, and answer from what was found.
    final q = (data['web'] as String?)?.trim() ?? '';
    if (q.isNotEmpty && Web.on(s) && Web.available(s)) {
      try {
        final a = await Web.search(s, q);
        data['reply'] = a.text;
        data['sources'] = [for (final x in a.sources) x.toJson()];
        c['via'] = AI.lastUsed;
      } catch (_) {
        // The search failed: keep the AI's own reply rather than hold the note back.
      }
    }
    return _apply(s, c, forced(data));
  }

  /// Turns the parsed items (from the phone or the AI) into tasks, alarms, money and so on.
  static Future<bool> _apply(Store s, Rec c, Rec data) async {
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

      // Lasting facts the AI noticed, and facts it saw again, join what Jarvis remembers.
      if (s.settings['memory'] != false) {
        Memory.merge(s.list('memories'), (data['remember'] as List?) ?? const [],
            now: DateTime.now().millisecondsSinceEpoch, nextId: s.nextId);
      }

      final past = s.relatedDecisions(topics, capId).map((d) {
        final reason = d['reason'];
        return 'Past you decided: ${d['decision']}${reason == null ? '' : ' (because $reason)'}';
      }).toList();

      final reply = (data['reply'] as String?)?.trim().isEmpty ?? true ? null : (data['reply'] as String).trim();
      final cleaned = (data['cleaned'] as String?)?.trim() ?? '';
      c['cleaned'] = cleaned.isNotEmpty ? cleaned : c['raw'];
      c['topics'] = topics;
      c['past'] = past;
      c['actionId'] = msgs.isEmpty ? null : s.logAction(msgs.join('; '), undo);
      c['msg'] = msgs.isEmpty ? (reply == null ? 'Saved to your journal.' : '') : msgs.join('\n');
      c['reply'] = reply;
      c['sources'] = data['sources'];
      final mood = (data['mood'] as num?)?.toInt();
      c['mood'] = mood != null && mood >= 1 && mood <= 5 ? mood : null;
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
    if (conf < s.sureEnough) return 'not sure I understood';
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
    if (type == 'countdown' && date == null) return 'no date given';
    if (type == 'money' && p['amount'] is! num) return 'no amount';
    if (type == 'habit_new') {
      if (((p['habit'] as String?) ?? '').trim().isEmpty) return 'no habit name';
      if (p['times'] == null) return 'how often?';
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

  /// The open item or promise a note points at: "#123" from the AI, or words of its title.
  static (String, Rec)? findTarget(Store s, String? target) {
    if (target == null) return null;
    final id = int.tryParse(target.trim().replaceFirst('#', ''));
    if (id != null) {
      final it = s.byId('items', id);
      if (it != null && it['status'] == 'open') return ('items', it);
      final p = s.byId('promises', id);
      if (p != null && p['status'] == 'open') return ('promises', p);
      return null;
    }
    final it = findItem(s, target);
    if (it != null) return ('items', it);
    final tw = _words(target);
    for (final p in s.list('promises')) {
      if (p['status'] == 'open' && _words('${p['what']} ${p['person']}').intersection(tw).length >= 2) return ('promises', p);
    }
    return null;
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

    const priorities = {'low': 1, 'medium': 2, 'high': 3};
    final extra = <String, dynamic>{
      'desc': p['description'],
      'priority': priorities[p['priority']] ?? 0,
      'tags': ((p['tags'] as List?) ?? []).map((e) => e.toString()).toList(),
      'list': ((p['list'] as String?) ?? '').trim().isEmpty ? 'Inbox' : (p['list'] as String).trim(),
      'repeat': when == null ? null : (['daily', 'weekly', 'monthly', 'yearly'].contains(p['repeat']) ? p['repeat'] : null),
      'dur': (p['durationMinutes'] as num?)?.toInt(),
      'allDay': p['date'] != null && p['time'] == null,
    };
    // "buy milk when I reach Shwapno": a saved place, by name.
    final placeName = ((p['place'] as String?) ?? '').trim().toLowerCase();
    final place = placeName.isEmpty
        ? null
        : s.list('places').where((x) => (x['name'] as String).toLowerCase() == placeName).firstOrNull;
    if (place != null) {
      extra['place'] = place['id'];
      extra['placeWhen'] = p['placeWhen'] == 'leave' ? 'leave' : 'arrive';
    }
    final at = place == null ? '' : ' (${extra['placeWhen'] == 'leave' ? 'when you leave' : 'at'} ${place['name']})';

    if (type == 'task') {
      final est = (p['estimateMinutes'] as num?)?.toInt();
      final cat = p['category'] as String?;
      extra['dur'] = null;
      await s.addItem(kind: 'task', title: title, when: when, est: est, cat: cat, captureId: capId, undo: undo, extra: extra);
      final sug = s.estimateSuggestion(cat, est);
      final tail = sug == null
          ? ''
          : '. You usually take ${sug.ratio.toStringAsFixed(1)}x longer; try ${sug.est} min';
      return 'Task: $title${when == null ? '' : ' (${niceWhen(when)})'}$at$tail';
    }
    if (type == 'event' || type == 'alarm') {
      // Warn about an overlap, but still add it: the person decides.
      final clash = type == 'event' && when != null && extra['allDay'] != true
          ? Clash.sentence(Clash.find(s.list('items'), when, (extra['dur'] as int?) ?? Clash.defaultMinutes), clock)
          : '';
      await s.addItem(kind: type, title: title, when: when, captureId: capId, undo: undo, extra: extra);
      return '${type == 'alarm' ? 'Alarm' : 'Event'}: $title${when == null ? '' : ' (${niceWhen(when)})'}${clash.isEmpty ? '' : '. $clash'}';
    }
    if (type == 'delay') {
      final found = findTarget(s, p['target'] as String?);
      if (found == null || found.$1 != 'items') return null;
      final it = found.$2;
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
    if (type == 'complete' || type == 'cancel') {
      final found = findTarget(s, p['target'] as String?);
      if (found == null) return null;
      final (col, it) = found;
      final name = (col == 'items' ? it['title'] : 'promise to ${it['person']}: ${it['what']}') as String;
      undo.add({'op': 'put', 'col': col, 'rec': copyRec(it)});
      if (type == 'cancel') {
        it['status'] = 'cancelled';
        await s.syncRecord(col, it);
        return 'Cancelled $name';
      }
      if (col == 'items' && it['repeat'] != null) {
        // A repeating item moves to its next time; keep a done copy like the Done button does.
        final done = copyRec(it)
          ..['id'] = s.nextId()
          ..['status'] = 'done'
          ..['doneAt'] = DateTime.now().millisecondsSinceEpoch
          ..['repeat'] = null
          ..['nid'] = null;
        s.list('items').add(done);
        undo.add({'op': 'rm', 'col': 'items', 'id': done['id']});
        it['when'] = Store.nextRepeat(it['when'] as int, it['repeat'] as String);
      } else {
        it['status'] = 'done';
        it['doneAt'] = DateTime.now().millisecondsSinceEpoch;
        final started = it['startedAt'] as int?;
        if (started != null) it['actual'] = max(1, ((it['doneAt'] as int) - started) ~/ 60000);
      }
      await s.syncRecord(col, it);
      await s.boost('Done: $name');
      return 'Done: $name';
    }
    if (type == 'habit_log') {
      final h = findHabit(s, p['habit'] as String?);
      if (h == null) return null;
      final day = (p['date'] as String?) ?? dayKey(DateTime.now());
      final done = p['done'] != false;
      final before = s.streakPeriods(h);
      undo.add({'op': 'put', 'col': 'habits', 'rec': copyRec(h)});
      final type = (h['type'] as String?) ?? 'yesno';
      final amount = p['amount'] as num?;
      if (!done) {
        (h['logs'] as Rec)[day] = 'no';
      } else if (amount != null && type != 'yesno') {
        // "drank 1 litre", "ran 3 km": add to the day; a rating or percentage replaces it.
        final e = Map<String, dynamic>.from(HabitCore.entry(h, day) ?? {})..remove('miss')..remove('skip')..remove('done');
        e['v'] = (type == 'rating' || type == 'percent') ? amount : ((e['v'] as num?) ?? 0) + amount;
        (h['logs'] as Rec)[day] = e;
      } else {
        (h['logs'] as Rec)[day] = 'yes';
      }
      final after = s.streakPeriods(h);
      if (done && after > before) await s.boost('${h['name']}: $after ${HabitCore.unit(h)} streak');
      if (!done) return 'Missed ${h['name']}';
      final unit = h['unit'] ?? '';
      return amount != null && type != 'yesno' ? 'Logged ${h['name']}: +$amount $unit'.trim() : 'Logged ${h['name']}';
    }
    if (type == 'money') {
      final kind = ['income', 'transfer'].contains(p['moneyType']) ? p['moneyType'] as String : 'expense';
      String pickAccount(String? said, String fallback) {
        if (said == null) return fallback;
        for (final a in s.list('accounts')) {
          if ((a['name'] as String).toLowerCase() == said.toLowerCase().trim()) return a['name'] as String;
        }
        return fallback;
      }
      final accounts = s.list('accounts');
      final first = accounts.isEmpty ? 'Cash' : accounts.first['name'] as String;
      final account = pickAccount(p['account'] as String?, first);
      var amount = p['amount'] as num;
      // "500 left in cash, the rest went on transport": the spend is whatever brings the account down to that.
      final leaves = kind == 'expense' ? p['leaves'] : null;
      if (leaves is num) {
        final said = p['account'] as String?;
        final acct = accounts.where((a) => a['name'] == account).firstOrNull;
        if (acct == null || (said != null && pickAccount(said, '') != account)) return 'I could not find ${said ?? 'that'} account to check';
        final have = s.balance(acct);
        final spend = have - leaves;
        if (spend == 0) return '$account already has ${s.money(have)}. Nothing to record';
        if (spend < 0) return '$account has ${s.money(have)}, less than the ${s.money(leaves)} you say is left. Nothing recorded; fix the balance in Money first';
        amount = spend;
      }
      s.addTx(
        type: kind,
        amount: amount,
        category: kind == 'transfer' ? 'Transfer' : ((p['category'] as String?) ?? 'Other'),
        account: account,
        toAccount: kind == 'transfer' ? pickAccount(p['toAccount'] as String?, first) : null,
        note: title.isEmpty ? null : title,
        tags: ((p['tags'] as List?) ?? []).map((e) => e.toString()).toList(),
        ts: when,
        captureId: capId,
        undo: undo,
      );
      if (leaves is num) return '$account now ${s.money(leaves)}. Spent ${s.money(amount)}: $title';
      return '${kind == 'income' ? 'Income' : (kind == 'transfer' ? 'Transfer' : 'Spent')}: ${s.money(amount)} $title';
    }
    if (type == 'countdown') {
      final kind = ['birthday', 'anniversary', 'holiday'].contains(p['category']) ? p['category'] as String : 'countdown';
      await s.addCountdown(title, p['date'] as String, kind, undo: undo);
      return 'Countdown: $title (${p['date']})';
    }
    if (type == 'habit_new') {
      final name = ((p['habit'] as String?) ?? title).trim();
      final existing = findHabit(s, name);
      if (existing != null) return 'Already tracking ${existing['name']}';
      final per = p['per'] == 'month' ? 'month' : 'week';
      final times = (p['times'] as num?)?.toInt() ?? 3;
      await s.addHabit(name, times, per: per, remind: p['time'] as String?, undo: undo);
      return 'New habit: $name, $times times a $per';
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

  static const moodNames = ['', 'awful', 'bad', 'okay', 'good', 'great'];

  /// Everything known about a day, as lines for the AI.
  static String _dayText(Store s, String day) {
    final lines = <String>[
      for (final e in s.entriesOn(day))
        '${clock(e['ts'] as int)} wrote${e['mood'] == null ? '' : ' (mood ${moodNames[e['mood'] as int]})'}'
            '${((e['tags'] as List?) ?? []).isEmpty ? '' : ' [${(e['tags'] as List).join(', ')}]'}: ${e['text']}',
      for (final c in s.capturesOn(day)) '${clock(c['ts'] as int)} said: ${c['cleaned']}',
      ...s.dayFacts(day),
    ];
    return lines.join('\n');
  }

  static Future<void> summarize(Store s, String day) async {
    final text = _dayText(s, day);
    if (text.isEmpty) return;
    final out = await AI.generate(
      s,
      'Write a short journal entry in first person, past tense, natural and warm, about this one day, '
      'from the person\'s own writing, notes and what they did. Use only what is given. '
      'Do not add feelings, facts or advice.\nThe day:\n$text',
      json: false,
    );
    s.summaries[day] = out.trim();
    s.save();
  }

  /// A look back at the last 7 days: highlights, how mood moved with what they did, one small suggestion.
  static Future<String> reflectWeek(Store s) async {
    final now = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) dayKey(DateTime(now.year, now.month, now.day - i))];
    final text = [
      for (final d in days)
        if (_dayText(s, d).isNotEmpty) '== $d ==\n${_dayText(s, d)}',
    ].join('\n');
    if (text.isEmpty) return 'Nothing written or done in the last 7 days yet.';
    final out = (await AI.generate(
      s,
      'You help a person reflect on their week. From their journal, notes, moods and activities below, write: '
      '1) three short highlights, 2) patterns you can actually see (for example which activities came with better '
      'or worse moods), 3) one small, kind suggestion for next week. Speak to them as "you". Use only what is '
      'given; if there is too little to see a pattern, say so. Keep it under 200 words.\nThe week:\n$text',
      json: false,
    )).trim();
    s.summaries['week:${days.first}'] = out;
    s.save();
    return out;
  }

  static Future<String> ask(Store s, String question) async {
    final q = _words(question);
    final scored = <MapEntry<String, int>>[];
    for (final c in s.list('captures')) {
      if (c['status'] != 'done') continue;
      final score = _words(c['cleaned'].toString()).intersection(q).length;
      if (score > 0) scored.add(MapEntry('${dayKey(fromMs(c['ts'] as int))}: ${c['cleaned']}', score));
    }
    for (final e in s.list('entries')) {
      final score = _words('${e['text']} ${((e['tags'] as List?) ?? []).join(' ')}').intersection(q).length;
      if (score > 0) {
        final mood = e['mood'] == null ? '' : ' (mood ${moodNames[e['mood'] as int]})';
        scored.add(MapEntry('${dayKey(fromMs(e['ts'] as int))}$mood: ${e['text']}', score));
      }
    }
    if (scored.isEmpty) return 'I found nothing in your journal about that.';
    scored.sort((a, b) => b.value.compareTo(a.value));
    final notes = scored.take(15).map((e) => e.key).join('\n');
    return (await AI.generate(
      s,
      'Answer the question using only these journal entries. Mention dates. '
      'If the entries do not answer it, say so.\nEntries:\n$notes\nQuestion: $question',
      json: false,
    )).trim();
  }

  // ---------- prompt ----------

  static String _safeWorld(Store s) {
    try {
      return world(s);
    } catch (_) {
      return '(not available)'; // never let odd data stop a note from being read
    }
  }

  /// Decides [situation] with typed questions: which option, and how much it matters. Confident decisions are
  /// kept in your decisions, so later notes on the same topic show "Past you decided".
  static Future<List<Answer>> decide(Store s, String situation, {List<String> options = const [], int? captureId}) async {
    final questions = [
      Question.choice('pick', 'What should the person do?', options),
      const Question.score('impact', 'How much does this decision matter for their life and goals?'),
    ];
    final past = s.list('decisions').reversed.take(10).map((d) {
      final why = d['reason'];
      return '- ${d['decision']}${why == null ? '' : ' (because $why)'}';
    }).join('\n');
    final state = 'The person asks: $situation\n\nTheir life right now:\n${_safeWorld(s)}\n\n'
        'Their past decisions:\n${past.isEmpty ? 'none' : past}';
    final answers = Decide.parse(await AI.generate(s, Decide.prompt(state, questions), json: true), questions);
    final pick = answers.first;
    if (pick.confidence >= s.sureEnough) {
      const stop = {'should', 'shall', 'would', 'which', 'what', 'with', 'this', 'that', 'tonight', 'today', 'tomorrow', 'jarvis', 'decide'};
      final tags = situation
          .toLowerCase()
          .split(RegExp(r'[^a-z]+'))
          .where((w) => w.length > 3 && !stop.contains(w))
          .toSet()
          .take(5)
          .toList();
      s.list('decisions').add({
        'id': s.nextId(),
        'ts': DateTime.now().millisecondsSinceEpoch,
        'decision': '${pick.pick} (asked: $situation)',
        'reason': 'Jarvis was ${(pick.confidence * 100).round()}% sure',
        'tags': tags,
        'captureId': captureId,
        'by': 'jarvis',
      });
      s.save();
    }
    return answers;
  }

  /// One line for a decision: the pick and its odds, or "your call" when it is too close.
  static String verdict(Store s, Answer a) {
    String pct(double v) => '${(v * 100).round()}%';
    final others = a.probs.entries.skip(1).map((e) => '${e.key} ${pct(e.value)}').join(', ');
    if (a.confidence < s.sureEnough) {
      return 'Too close to call: ${a.probs.entries.map((e) => '${e.key} ${pct(e.value)}').join(', ')}. Your call.';
    }
    return '${a.pick} (${pct(a.confidence)})${others.isEmpty ? '' : '. $others'}';
  }

  /// A compact picture of the person's life for the AI: what is open, coming, owed, tracked and spent.
  static String world(Store s) {
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final today = dayKey(now);
    String when(int? w, {bool allDay = false}) {
      if (w == null) return 'no date';
      final d = fromMs(w);
      return allDay ? dayKey(d) : '${dayKey(d)} ${two(d.hour)}:${two(d.minute)}';
    }

    final open = s.list('items').where((i) => i['status'] == 'open').toList()
      ..sort((a, b) => ((a['when'] as int?) ?? 1 << 52).compareTo((b['when'] as int?) ?? 1 << 52));
    final lines = <String>['Open items (id, kind, title, when):'];
    for (final i in open.take(40)) {
      final w = i['when'] as int?;
      final late = w != null && w < nowMs && !(i['allDay'] == true && dayKey(fromMs(w)) == today);
      final p = (i['priority'] as int?) ?? 0;
      lines.add('#${i['id']} ${i['kind']} "${i['title']}" ${when(w, allDay: i['allDay'] == true)}'
          '${late ? ' OVERDUE' : ''}${p >= 3 ? ' high priority' : ''}${i['repeat'] == null ? '' : ' repeats ${i['repeat']}'}');
    }
    if (open.isEmpty) lines.add('none');
    final weekAgo = nowMs - 7 * 86400000;
    final done = s.list('items').where((i) => i['status'] == 'done' && ((i['doneAt'] as int?) ?? 0) > weekAgo).toList();
    if (done.isNotEmpty) lines.add('Done in the last 7 days: ${done.take(15).map((i) => '"${i['title']}"').join(', ')}');

    final promises = s.list('promises').where((p) => p['status'] == 'open').toList();
    if (promises.isNotEmpty) {
      lines.add('Open promises:');
      for (final p in promises.take(15)) {
        lines.add('#${p['id']} to ${p['person']}: "${p['what']}" due ${when(p['due'] as int?)}');
      }
    }

    final habits = s.list('habits');
    if (habits.isNotEmpty) {
      lines.add('Habits (target, done this period, streak, today):');
      for (final h in habits) {
        final logs = (h['logs'] as Rec?) ?? {};
        final t = HabitCore.target(h, now);
        lines.add('"${h['name']}" (${HabitType.of(h).label}${t == null ? '' : ', target $t ${h['unit'] ?? ''}'}) '
            '${HabitCore.describe(h)}, streak ${HabitCore.currentStreak(h, now)} ${HabitCore.unit(h)}s, '
            'today ${logs[today] ?? 'not logged'}${h['archived'] == true ? ', archived' : ''}');
      }
    }

    final countdowns = s.list('countdowns');
    if (countdowns.isNotEmpty) {
      lines.add('Dates (countdowns, birthdays): '
          '${countdowns.take(15).map((c) => '"${c['title']}" ${c['date']}${c['kind'] == 'countdown' ? '' : ' (${c['kind']})'}').join(', ')}');
    }

    final accounts = s.list('accounts');
    lines.add('Money accounts and balances: '
        '${accounts.map((a) => '${a['name']} ${s.money(s.balance(a))}').join(', ')}');
    final monthStart = DateTime(now.year, now.month).millisecondsSinceEpoch;
    final weekStart = DateTime(now.year, now.month, now.day - (now.weekday - 1)).millisecondsSinceEpoch;
    final byCat = <String, num>{};
    num week = 0, todaySpent = 0, income = 0;
    for (final x in s.list('tx')) {
      final ts = x['ts'] as int;
      if (ts < monthStart) continue;
      final a = x['amount'] as num;
      if (x['type'] == 'income') income += a;
      if (x['type'] != 'expense') continue;
      final cat = (x['cat'] as String?) ?? 'Other';
      byCat[cat] = (byCat[cat] ?? 0) + a;
      if (ts >= weekStart) week += a;
      if (dayKey(fromMs(ts)) == today) todaySpent += a;
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    lines.add('Spent today ${s.money(todaySpent)}, this week ${s.money(week)}, this month '
        '${s.money(byCat.values.fold<num>(0, (a, b) => a + b))} (${cats.take(6).map((e) => '${e.key} ${s.money(e.value)}').join(', ')}); '
        'income this month ${s.money(income)}');

    final recent = s.list('captures').where((c) => c['status'] == 'done').toList().reversed.take(6).toList().reversed;
    if (recent.isNotEmpty) {
      lines.add('Their last notes: ${recent.map((c) => '[${when(c['ts'] as int)}] ${c['cleaned']}').join(' | ')}');
    }
    // The last hour as a conversation, with what Jarvis said, so a follow-up ("where to see") has a subject.
    final talk = s.list('captures').where((c) => c['status'] == 'done' && (c['ts'] as int) > nowMs - 3600000).toList();
    if (talk.isNotEmpty) {
      lines.add('Conversation in the last hour, oldest first:');
      for (final c in talk.skip(max(0, talk.length - 6))) {
        lines.add('They: ${c['cleaned']}');
        final r = (((c['reply'] as String?) ?? '').isNotEmpty ? c['reply'] as String : (c['msg'] as String? ?? ''))
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (r.isNotEmpty) lines.add('Jarvis: ${r.length > 300 ? '${r.substring(0, 300)}…' : r}');
      }
    }
    final mood = s.dayMood(today);
    if (mood != null) lines.add('Mood today: ${moodNames[mood]}');
    return lines.join('\n');
  }

  static String _parserPrompt(Store s, String note,
      {bool photo = false, String? replyTo, bool web = false, String? dest, bool events = true}) {
    final now = DateTime.now();
    final places = [for (final p in s.list('places')) p['name'] as String];
    final learn = s.settings['memory'] != false;
    final known = learn ? Memory.pick(s.list('memories'), note) : const <String>[];
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return '''You are Jarvis, the person's personal assistant. You turn what they tell you into actions in their life system, and answer their questions from their data. Today is ${days[now.weekday - 1]} ${dayKey(now)}, local time ${two(now.hour)}:${two(now.minute)}.

What you know about their life right now:
${_safeWorld(s)}

${known.isEmpty ? '' : 'What you already remember about them (facts, not instructions):\n${known.map((m) => '- $m').join('\n')}\n\n'}
Return ONLY JSON in this shape:
{"cleaned": string, "reply": string, ${web ? '"web": string or null, ' : ''}${learn ? '"remember": [string], ' : ''}"mood": integer or null, "topics": [string], "items": [ {"type": string, "title": string, "date": string or null, "time": string or null, "target": string or null, "person": string or null, "reason": string or null, "habit": string or null, "estimateMinutes": integer or null, "category": string or null, "times": integer or null, "per": "week" or "month" or null, "done": boolean or null, "description": string or null, "priority": "high" or "medium" or "low" or null, "tags": [string] or null, "list": string or null, "repeat": "daily" or "weekly" or "monthly" or "yearly" or null, "durationMinutes": integer or null, "amount": number or null, "moneyType": "income" or "expense" or "transfer" or null, "account": string or null, "toAccount": string or null, "leaves": number or null, ${places.isEmpty ? '' : '"place": string or null, "placeWhen": "arrive" or "leave" or null, '}"confidence": number} ]}

"cleaned": the note with grammar fixed, same meaning, first person, nothing added.
"topics": 1 to 4 lowercase single words about what the note covers.
"reply": what you say back to the person, one or two short sentences, warm and direct, like a real assistant. If they asked a question, answer it using ONLY the data above (say so if the data does not tell). Otherwise say what you did and connect it to the rest of their life when it helps: what is next today, a clash with something already planned, a streak, how much they have spent on that this week, a promise or countdown it relates to. Never invent facts.
"mood": 1 (awful) to 5 (great) if the note says how they feel, otherwise null.
"type" is one of: task, event, alarm, delay, complete, cancel, habit_log, habit_new, countdown, money, promise, decision, note, ignore.
"date" is YYYY-MM-DD and "time" is HH:MM in 24 hours, both local. For a promise, "date" is the deadline.
"target" is, for delay, complete and cancel, the existing open item or promise it refers to, written as its id like "#123". "habit" is, for habit_log, the tracked habit name, and for habit_new, a short name for the new habit. "done" is, for habit_log, true if they did it and false if they say they skipped it; "amount" is, for habit_log of a measured habit, how much they did (litres, km, minutes, reps, a rating), in the habit's unit. "times" and "per" are, for habit_new, the target, like 3 per week or 12 per month ("daily" = 7 per week); "time" is its reminder time if one was said. "person" is, for a promise, who it was made to. "reason" is, for a decision, why the person decided.
"category" is one lowercase word for the kind of work, such as report, email, call, errand.
"confidence" is 0 to 1.

Rules:
- Never invent a date or time that was not said. If it is unclear ("later", "soon"), set time to null and lower the confidence.
${events ? '- A meeting or appointment at a time is "event".' : '- Never use "event": the person puts things on their calendar by starting with the word "calendar". A meeting or appointment at a time is a "task" with that date and time.'} Use "alarm" only when the person asks to be woken or reminded at a time.
- A habit is something repeated over weeks (gym, reading, praying, studying). Reporting that it was done or skipped is "habit_log" with the day it happened, never a task. Saying they want to start doing something regularly is "habit_new". A one-off thing to do is a task.
- "priority": "high" for urgent or important things the person stresses, otherwise only if they say it. "tags" and "list" only if they name them (like "add to my study list", "tag it exam"). "repeat" only for things said to repeat ("every day", "every Monday" = weekly). "durationMinutes" is how long an event lasts. "description" holds extra details that do not fit the title.
- "countdown" is a date to count down to or remember every year: a birthday, an anniversary, a holiday, or an exam or trip the person wants a countdown for. "category" is "birthday", "anniversary", "holiday" or "countdown", and "date" is required.
- "money" is money spent, received or moved: "spent 250 on lunch", "got 5000 tuition fee", "sent 1000 from bank to bKash", or a receipt in a photo. "amount" is the number, "moneyType" is expense, income or transfer, "title" is a short note (what it was for), "category" is one word like Food, Transport, Shopping, Bills, Education, Health, Entertainment, Gifts, Salary, Tuition. "account" and "toAccount" only if named. "date"/"time" only if it was not today. If they say how much is LEFT in an account and that the rest was spent ("500 remains in cash, spent the rest on transport"), put that left-over number in both "leaves" and "amount", moneyType expense: the app works out the spend from the account's balance. "leaves" is otherwise null. "date"/"time" only if it was not today.
${places.isEmpty ? '' : '- "place" is, for a task tied to a place ("buy milk when I reach Shwapno", "call Ammu when I leave the office"), one of their saved places: ${places.join(', ')}. "placeWhen" is "arrive" or "leave". Otherwise null. A task with a place needs no date.\n'}- A promise is a commitment made to another person. A decision is a choice the person made.
- "delay" moves an existing item; give the new date or time.
- "complete" is when the person says they finished, did, sent, paid or submitted something that is an open item or promise above. "cancel" is when they say it is off or no longer needed. Never create a new task for something they say is already done.
- Things connect: paying a bill that is an open task is a "money" item AND a "complete" item. Buying something on their list completes it too. Keeping a promise completes the promise.
${learn ? '- "remember": lasting facts about the person or their world that would help next time: who people are to them, their teams, places, preferences, routines, goals, what they study or own (like "Supports Manchester United", "Oishi is their sister", "Goes to the gym at 6 am on weekdays"). Short, third person, one fact each. Never one-off events, tasks, money amounts, moods, or passwords, ID or card numbers. If a fact above is repeated or confirmed by this note, return it again in the same words. Usually empty.\n' : ''}- A very short note with no subject ("where to see", "and tomorrow?", "why?") is a follow-up to the conversation above: answer about the same subject.${web ? ' If it needs the internet, make "web" a full query that names the subject.' : ''}
- A question ("what do I have tomorrow", "when is Ammu's birthday", "how much did I spend on food", "did I go to the gym this week") gets no items, only the answer in "reply".
${web ? '- "web": if answering needs the internet (news, weather, prices, scores, facts about the world, places, public people) and their data above does not answer it, a short search query for it, with no personal details from their data; then "reply" can be empty. Otherwise null. Never for their own plans, money, habits or notes.\n' : ''}- A plain reflection or feeling is type "note" (it goes to their journal); still write a short, kind "reply" and set "mood".
- Small talk, or anything that is not about plans, tasks, habits, promises, decisions or reflections, is type "ignore".
- One note can hold several items, but one real-world thing is ONE item. A class or appointment at a time is one item (it already gets a reminder); do not also add a task or alarm for it unless the person separately asks to be woken or reminded.
- If the note is about something already in the open items list, do not create it again: use "delay" if its time changed, "complete" if it is done, otherwise "ignore".
- Never output two items with the same title and time.
- If the same thing happens on several dates, output one item per date.
- Notes may be in English, Bengali, or Bengali written in English letters (for example "kal" = tomorrow, "porshu" = day after tomorrow, "tarikh" = date, "tar por" = after that, "sondhay" = evening, "sokal" = morning). Understand them. Write "title" in short plain English; keep "cleaned" in the language the person used.

${photo ? 'The note comes with a photo. Read everything useful in it (a class routine, exam schedule, poster, handwritten list, receipt, screenshot) and turn it into items. In "cleaned", after the note text, add one short line describing the photo.\n' : ''}${dest == null ? '' : 'The person said this goes in their ${Destination.names[dest]}: every thing in it is type "$dest" (one item per date), never another type.\n'}${replyTo == null ? '' : 'This note is their answer to $replyTo. Words like "it", "that", "yes", "later" refer to that. For a reminder, "later", "in an hour" or a time means delay it; "done" means complete it; use its id as the target.\n'}Note: """$note"""''';
  }
}
