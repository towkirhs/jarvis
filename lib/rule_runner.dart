import 'dart:async';

import 'cal_edit.dart';
import 'cal_index.dart';
import 'habit_core.dart';
import 'native.dart';
import 'rules.dart';
import 'store.dart';

/// Answers the rules' conditions from the Store.
class _Facts implements RuleFacts {
  _Facts(this.s);
  final Store s;
  @override
  final DateTime now = DateTime.now();

  @override
  num? balance(String account) {
    for (final a in s.list('accounts')) {
      if ('${a['name']}'.toLowerCase() == account.trim().toLowerCase()) return s.balance(a);
    }
    return null;
  }

  @override
  num spent(String? category, DateTime from) {
    num sum = 0;
    for (final t in s.list('tx')) {
      if (t['type'] != 'expense' || (t['ts'] as int) < from.millisecondsSinceEpoch) continue;
      if (category != null && '${t['cat']}'.toLowerCase() != category.toLowerCase()) continue;
      sum += t['amount'] as num;
    }
    return sum;
  }

  @override
  bool habitDone(String habit) {
    final h = RuleRunner.habit(s, habit);
    return h != null && HabitCore.done(h.cast<String, dynamic>(), now);
  }

  @override
  bool taskOpen(String text) => RuleRunner.openTask(s, text) != null;
}

/// Carries out rules when something happens. Changes a rule makes do not set off other rules,
/// so rules cannot loop. Each firing is one entry in the action log, with Undo.
class RuleRunner {
  static bool _has(Object? hay, String needle) {
    final words = needle.toLowerCase().split(RegExp(r'[^a-z0-9ঀ-৿]+')).where((w) => w.length >= 3).toList();
    if (words.isEmpty) return false;
    final h = '${hay ?? ''}'.toLowerCase();
    return words.every(h.contains);
  }

  static Rec? habit(Store s, String name) {
    for (final h in s.list('habits')) {
      if (h['archived'] != true && '${h['name']}'.trim().toLowerCase() == name.trim().toLowerCase()) return h;
    }
    return null;
  }

  static final _pay = RegExp(r'\b(pay|paid|bill|bills|recharge|fee|fees|rent)\b', caseSensitive: false);

  /// The open task whose title holds every word of [text], or null.
  static Rec? openTask(Store s, String text, {bool payOnly = false}) {
    for (final i in s.list('items')) {
      if (i['status'] != 'open' || i['kind'] != 'task') continue;
      if (payOnly && !_pay.hasMatch('${i['title']}')) continue;
      if (_has(i['title'], text)) return i;
    }
    return null;
  }

  /// Runs every switched-on rule that [events] set off.
  static void run(Store s, List<RuleEvent> events) {
    if (events.isEmpty) return;
    final f = _Facts(s);
    for (final rule in [...s.list('rules')]) {
      if (rule['on'] != true) continue;
      for (final e in events) {
        if (rule['on'] != true) break; // a "once" rule that just fired
        if (Rules.matches(rule, e) && Rules.holds(rule, f)) fire(s, rule, e);
      }
    }
  }

  /// Time rules and events that ended since the last check. Called every minute and when Jarvis comes back.
  static void tick(Store s) {
    final now = DateTime.now();
    final raw = int.tryParse(s.local('ruleTick') ?? '');
    unawaited(s.setLocal('ruleTick', '${now.millisecondsSinceEpoch}'));
    if (raw == null) return; // the first run: nothing to catch up on
    var last = DateTime.fromMillisecondsSinceEpoch(raw);
    final floor = DateTime(now.year, now.month, now.day - 1);
    if (last.isBefore(floor)) last = floor;
    if (!now.isAfter(last)) return;

    final events = <RuleEvent>[];
    final index = CalIndex.build(s.calendarItems, last, now);
    for (final day in index.values) {
      for (final e in day) {
        if (e.item['allDay'] == true || e.item['kind'] != 'event' || !e.firstDay) continue;
        final end = e.start.add(Duration(minutes: CalEdit.minutes(e.item)));
        if (end.isAfter(last) && !end.isAfter(now)) events.add(RuleEvent('event_end', {'title': e.item['title'] ?? ''}));
      }
    }
    run(s, events);

    final f = _Facts(s);
    for (final rule in [...s.list('rules')]) {
      if (rule['on'] == true && Rules.dueAt(rule, last, now) && Rules.holds(rule, f)) {
        fire(s, rule, const RuleEvent('time', {}));
      }
    }
  }

  /// Does what the rule says, logs it with Undo, and tells the person which rule did it.
  static void fire(Store s, Rec rule, RuleEvent e) {
    final undo = <Rec>[
      {'op': 'put', 'col': 'rules', 'rec': copyRec(rule)},
    ];
    final did = <String>[];
    String fill(Object? t) => Rules.fill('${t ?? ''}', e, money: s.money);
    final now = DateTime.now();
    for (final a in (rule['then'] as List?) ?? const []) {
      if (a is! Map) continue;
      switch (a['do']) {
        case 'remind':
          final text = fill(a['text']);
          if (text.isEmpty) break;
          unawaited(Native.notify('Jarvis', text));
          did.add('reminded you: $text');
        case 'task':
          final title = fill(a['title']);
          if (title.isEmpty) break;
          final day = (a['day'] as num?)?.toInt() ?? 0;
          final at = a['time'] is String ? '${a['time']}'.split(':') : null;
          final when = at == null
              ? DateTime(now.year, now.month, now.day + day, 9)
              : DateTime(now.year, now.month, now.day + day, int.tryParse(at[0]) ?? 9, int.tryParse(at.last) ?? 0);
          unawaited(s.addItem(
            kind: 'task',
            title: title,
            when: when.millisecondsSinceEpoch,
            est: (a['est'] as num?)?.toInt(),
            undo: undo,
            extra: {'allDay': at == null, 'byRule': rule['id']},
          ));
          if (day == 0 && at == null) unawaited(Native.notify('Jarvis', title));
          did.add('added task "$title"');
        case 'done':
          final text = fill(a['text']);
          final t = openTask(s, text, payOnly: a['payOnly'] == true);
          if (t == null) break;
          undo.add({'op': 'put', 'col': 'items', 'rec': copyRec(t)});
          t['status'] = 'done';
          t['doneAt'] = now.millisecondsSinceEpoch;
          unawaited(s.syncRecord('items', t));
          did.add('ticked off "${t['title']}"');
        case 'habit':
          final h = habit(s, fill(a['habit']));
          if (h == null) break;
          final day = dayKey(now);
          if (HabitCore.done(h.cast<String, dynamic>(), now)) break;
          undo.add({'op': 'put', 'col': 'habits', 'rec': copyRec(h)});
          final type = (h['type'] as String?) ?? 'yesno';
          (h['logs'] as Rec)[day] = type == 'yesno' ? 'yes' : {'v': h['target'] ?? 1};
          did.add('logged ${h['name']}');
        case 'money':
          final amount = a['amount'] is num ? a['amount'] as num : e.data['amount'];
          if (amount is! num || amount <= 0) break;
          final type = (a['moneyType'] as String?) ?? 'expense';
          final account = (a['account'] as String?) ?? 'Cash';
          s.addTx(
            type: type,
            amount: amount,
            category: (a['category'] as String?) ?? 'Other',
            account: account,
            note: fill(a['note']).isEmpty ? null : fill(a['note']),
            undo: undo,
          );
          did.add('added ${type == 'income' ? 'income' : 'spending'} of ${s.money(amount)} to $account');
      }
    }
    if (did.isEmpty) return; // nothing to do this time (no matching task, no amount): the rule waits
    rule['fired'] = ((rule['fired'] as num?) ?? 0) + 1;
    rule['last'] = now.millisecondsSinceEpoch;
    if (rule['once'] == true) rule['on'] = false;
    final text = '${rule['name'] ?? 'Rule'}: ${did.join(', ')}';
    final id = s.logAction('Rule $text', undo);
    s.save();
    s.ruleNotice.value = (text: text, actionId: id);
  }
}
