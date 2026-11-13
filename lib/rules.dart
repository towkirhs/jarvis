/// "When this happens, if that is true, do this": the rules that tie Jarvis's parts together.
/// Pure Dart (no Store) so it can be tested on its own; `rule_runner.dart` carries the actions out.
///
/// A rule (collection `rules`):
/// ```
/// {id, name, on: true, once: false, builtin: null, fired: 0, last: ms,
///  when: {on: money | task_done | event_end | habit | rent | loan | item | time, ...filters},
///  if:   [{check: balance | spent | days | between | habit_done | task_open, ...}],
///  then: [{do: remind | task | done | habit | money, ...}]}
/// ```
/// Filters on `when`: money `moneyType`, `account`, `category`, `min`; task_done, event_end and item `text`
/// (words the title must hold); item `kind`; habit `habit`; loan `loanType` (gave or took); time `at` (HH:MM)
/// and `days` (1 = Monday). Texts in `then` may use {amount}, {title}, {account}, {category}, {note},
/// {person}, {room}, {habit} from what happened.
class RuleEvent {
  const RuleEvent(this.kind, this.data);
  final String kind;
  final Map<String, dynamic> data;

  @override
  String toString() => '$kind $data';
}

/// What the conditions need to know about the rest of Jarvis.
abstract class RuleFacts {
  DateTime get now;

  /// Balance of the named account, or null when there is no such account.
  num? balance(String account);

  /// Money spent in [category] (any category when null) since [from].
  num spent(String? category, DateTime from);
  bool habitDone(String habit);
  bool taskOpen(String text);
}

class Rules {
  static const triggers = {
    'money': 'Money is added',
    'task_done': 'A task is done',
    'event_end': 'An event ends',
    'habit': 'A habit is done',
    'rent': 'Rent is paid',
    'loan': 'A loan is recorded',
    'item': 'Something is added',
    'time': 'At a time',
  };
  static const checks = {
    'balance': 'Account balance',
    'spent': 'Spent in a category',
    'days': 'On certain days',
    'between': 'Between two times',
    'habit_done': 'A habit is done today',
    'task_open': 'A task is still open',
  };
  static const actions = {
    'remind': 'Remind me',
    'task': 'Add a task',
    'done': 'Mark a task done',
    'habit': 'Log a habit',
    'money': 'Add money',
  };

  /// The keys of what has happened so far: added money, rent and loans, done tasks, done habit days,
  /// added items. A save compares the keys before and after to find what just happened.
  static Set<String> seen(Map<String, dynamic> state, {required bool Function(Map h, String day) habitDone}) {
    final out = <String>{};
    for (final t in (state['tx'] as List?) ?? const []) {
      out.add('tx:${t['id']}');
    }
    for (final p in (state['rentPays'] as List?) ?? const []) {
      out.add('rent:${p['id']}');
    }
    for (final l in (state['loans'] as List?) ?? const []) {
      out.add('loan:${l['id']}');
    }
    for (final i in (state['items'] as List?) ?? const []) {
      out.add('item:${i['id']}');
      if (i['status'] == 'done') out.add('done:${i['id']}');
    }
    for (final h in (state['habits'] as List?) ?? const []) {
      final logs = h['logs'];
      if (logs is! Map) continue;
      for (final day in logs.keys) {
        if (habitDone(h as Map, '$day')) out.add('habit:${h['id']}:$day');
      }
    }
    return out;
  }

  /// What happened between two [seen] sets, read from [state] (the newer one).
  static List<RuleEvent> happened(Set<String> before, Set<String> after, Map<String, dynamic> state) {
    Map? find(String col, Object id) {
      for (final r in (state[col] as List?) ?? const []) {
        if ('${r['id']}' == '$id') return r as Map;
      }
      return null;
    }

    final out = <RuleEvent>[];
    for (final k in after.difference(before)) {
      final p = k.split(':');
      switch (p[0]) {
        case 'tx':
          final t = find('tx', p[1]);
          if (t == null) break;
          out.add(RuleEvent('money', {
            'moneyType': t['type'], 'amount': t['amount'], 'account': t['account'], 'toAccount': t['toAccount'],
            'category': t['cat'], 'note': t['note'] ?? '', 'title': t['note'] ?? t['cat'] ?? '',
          }));
        case 'rent':
          final r = find('rentPays', p[1]);
          if (r == null) break;
          final room = find('rooms', r['room'] ?? -1);
          out.add(RuleEvent('rent', {'amount': r['amount'], 'room': room?['number'] ?? '', 'method': r['method'], 'title': 'Rent room ${room?['number'] ?? ''}'}));
        case 'loan':
          final l = find('loans', p[1]);
          if (l == null) break;
          final who = find('loanPeople', l['person'] ?? -1);
          out.add(RuleEvent('loan', {'loanType': l['type'], 'amount': l['amount'], 'person': who?['name'] ?? '', 'method': l['method'], 'title': l['why'] ?? l['note'] ?? ''}));
        case 'done':
          final i = find('items', p[1]);
          if (i == null) break;
          out.add(RuleEvent('task_done', {'kind': i['kind'], 'title': i['title'] ?? '', 'list': i['list'], 'tags': i['tags']}));
        case 'item':
          final i = find('items', p[1]);
          // A repeating task's "done" copy and items made already done are not new things to react to.
          if (i == null || i['status'] != 'open') break;
          out.add(RuleEvent('item', {'kind': i['kind'], 'title': i['title'] ?? '', 'list': i['list']}));
        case 'habit':
          final h = find('habits', p[1]);
          if (h == null) break;
          out.add(RuleEvent('habit', {'habit': h['name'], 'title': h['name'], 'day': p[2]}));
      }
    }
    return out;
  }

  static bool _has(Object? hay, Object? needle) {
    final n = '${needle ?? ''}'.trim().toLowerCase();
    if (n.isEmpty) return true;
    final h = '${hay ?? ''}'.toLowerCase();
    return n.split(RegExp(r'\s+')).every(h.contains);
  }

  static bool _same(Object? a, Object? b) => b == null || '$b'.trim().isEmpty || '$a'.trim().toLowerCase() == '$b'.trim().toLowerCase();

  /// Whether [e] is what the rule's `when` waits for (filters only; conditions come after).
  static bool matches(Map rule, RuleEvent e) {
    final w = rule['when'];
    if (w is! Map || w['on'] != e.kind) return false;
    final d = e.data;
    switch (e.kind) {
      case 'money':
        if (!_same(d['moneyType'], w['moneyType'])) return false;
        if (!_same(d['account'], w['account']) && !(d['moneyType'] == 'transfer' && _same(d['toAccount'], w['account']))) return false;
        if (!_same(d['category'], w['category'])) return false;
        if (w['min'] is num && (d['amount'] as num? ?? 0) < (w['min'] as num)) return false;
        return true;
      case 'loan':
        return _same(d['loanType'], w['loanType']) && _has(d['person'], w['text']);
      case 'habit':
        return _same(d['habit'], w['habit']);
      case 'item':
        return _same(d['kind'], w['kind']) && _has(d['title'], w['text']);
      case 'task_done' || 'event_end':
        return _has(d['title'], w['text']);
      case 'rent':
        return _has(d['room'], w['text']);
      case 'time':
        return true;
    }
    return false;
  }

  static int? _minutes(Object? hhmm) {
    final p = '${hhmm ?? ''}'.split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    return h == null || m == null ? null : h * 60 + m;
  }

  /// Whether every condition holds. A condition that cannot be read (an unknown account) does not hold.
  static bool holds(Map rule, RuleFacts f) {
    for (final c in (rule['if'] as List?) ?? const []) {
      if (c is! Map || !_check(c, f)) return false;
    }
    return true;
  }

  static bool _cmp(num v, Map c) {
    if (c['atLeast'] is num && v < (c['atLeast'] as num)) return false;
    if (c['below'] is num && v >= (c['below'] as num)) return false;
    return true;
  }

  static bool _check(Map c, RuleFacts f) {
    final now = f.now;
    switch (c['check']) {
      case 'balance':
        final b = f.balance('${c['account'] ?? 'Cash'}');
        return b != null && _cmp(b, c);
      case 'spent':
        final from = switch (c['period']) {
          'day' => DateTime(now.year, now.month, now.day),
          'week' => DateTime(now.year, now.month, now.day - (now.weekday - 1)),
          _ => DateTime(now.year, now.month),
        };
        final cat = '${c['category'] ?? ''}'.trim();
        return _cmp(f.spent(cat.isEmpty ? null : cat, from), c);
      case 'days':
        final days = ((c['days'] as List?) ?? const []).map((e) => (e as num).toInt()).toSet();
        return days.isEmpty || days.contains(now.weekday);
      case 'between':
        final m = now.hour * 60 + now.minute;
        final a = _minutes(c['from']) ?? 0;
        final b = _minutes(c['to']) ?? 1440;
        return a <= b ? (m >= a && m < b) : (m >= a || m < b);
      case 'habit_done':
        return f.habitDone('${c['habit'] ?? ''}') != (c['not'] == true);
      case 'task_open':
        return f.taskOpen('${c['text'] ?? ''}') != (c['not'] == true);
    }
    return false;
  }

  /// [text] with {amount}, {title} and the like filled in from what happened.
  static String fill(String text, RuleEvent e, {String Function(num)? money}) => text.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
        final v = e.data[m[1]];
        if (v == null) return '';
        if (m[1] == 'amount' && v is num && money != null) return money(v);
        return '$v';
      }).trim();

  /// Time rules due in (after, now]: their time today fell in that stretch and today is one of their days.
  static bool dueAt(Map rule, DateTime after, DateTime now) {
    final w = rule['when'];
    if (w is! Map || w['on'] != 'time') return false;
    final m = _minutes(w['at']);
    if (m == null) return false;
    final days = ((w['days'] as List?) ?? const []).map((e) => (e as num).toInt()).toSet();
    if (days.isNotEmpty && !days.contains(now.weekday)) return false;
    final at = DateTime(now.year, now.month, now.day, m ~/ 60, m % 60);
    return at.isAfter(after) && !at.isAfter(now);
  }

  /// The rule in one sentence, for the rules page.
  static String describe(Map rule, {String Function(num)? money}) {
    String amt(Object? v) => v is num ? (money?.call(v) ?? '$v') : '$v';
    final w = (rule['when'] as Map?) ?? const {};
    final when = switch (w['on']) {
      'money' => 'When ${w['moneyType'] == null ? 'money' : '${w['moneyType']}'} is added'
          '${w['account'] == null ? '' : ' to ${w['account']}'}${w['category'] == null ? '' : ' for ${w['category']}'}'
          '${w['min'] == null ? '' : ' (${amt(w['min'])} or more)'}',
      'task_done' => 'When a task${w['text'] == null ? '' : ' with "${w['text']}"'} is done',
      'event_end' => 'When an event${w['text'] == null ? '' : ' with "${w['text']}"'} ends',
      'habit' => 'When ${w['habit'] ?? 'a habit'} is done',
      'rent' => 'When rent is paid',
      'loan' => 'When ${w['loanType'] == 'took' ? 'I take' : w['loanType'] == 'gave' ? 'I give' : 'I record'} a loan',
      'item' => 'When ${w['kind'] == null ? 'something' : 'an ${w['kind']}'}${w['text'] == null ? '' : ' with "${w['text']}"'} is added',
      'time' => 'Every ${_days(w['days'])}at ${w['at']}',
      _ => 'When something happens',
    };
    final ifs = [
      for (final c in (rule['if'] as List?) ?? const [])
        if (c is Map)
          switch (c['check']) {
            'balance' => '${c['account'] ?? 'Cash'} has ${c['atLeast'] != null ? 'at least ${amt(c['atLeast'])}' : 'under ${amt(c['below'])}'}',
            'spent' => '${c['category'] ?? 'spending'} this ${c['period'] ?? 'month'} is ${c['atLeast'] != null ? 'at least ${amt(c['atLeast'])}' : 'under ${amt(c['below'])}'}',
            'days' => 'it is ${_days(c['days']).trim()}',
            'between' => 'it is between ${c['from'] ?? '00:00'} and ${c['to'] ?? '24:00'}',
            'habit_done' => '${c['habit']} is ${c['not'] == true ? 'not ' : ''}done today',
            'task_open' => '"${c['text']}" is ${c['not'] == true ? 'not ' : ''}open',
            _ => '?',
          },
    ];
    final thens = [
      for (final a in (rule['then'] as List?) ?? const [])
        if (a is Map)
          switch (a['do']) {
            'remind' => 'remind me: ${a['text']}',
            'task' => 'add task "${a['title']}"${(a['day'] as num? ?? 0) > 0 ? ' in ${a['day']} day(s)' : ''}',
            'done' => 'mark "${a['text']}" done',
            'habit' => 'log ${a['habit']}',
            'money' => 'add ${a['moneyType'] ?? 'expense'} ${a['amount'] == null ? '(same amount)' : amt(a['amount'])} to ${a['account'] ?? 'Cash'}',
            _ => '?',
          },
    ];
    return '$when${ifs.isEmpty ? '' : ', if ${ifs.join(' and ')}'}: ${thens.isEmpty ? 'nothing yet' : thens.join(', then ')}'
        '${rule['once'] == true ? ' (once)' : ''}.';
  }

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static String _days(Object? days) {
    final d = ((days as List?) ?? const []).map((e) => (e as num).toInt()).toList()..sort();
    if (d.isEmpty || d.length == 7) return 'day ';
    return '${d.map((x) => _dayNames[(x - 1) % 7]).join(', ')} ';
  }

  /// How an AI writes a rule (an item of type "rule" with a "rule" object). Shared by the app's prompt.
  static const aiSpec = '''- "rule" is for something that should happen only when something else happens or is true: "remind me to buy cream when I next add income to Cash", "when Cash has 2000 or more, remind me to pay Rahim", "every time I finish gym, log Walk", "when my class ends, add a task to revise". Never a timed task. "title" is a short name for the rule and "rule" is {"when": {...}, "if": [...], "then": [...], "once": true or false}.
  "when" is {"on": one of money, task_done, event_end, habit, rent, loan, item, time} plus filters: for money "moneyType" (income, expense, transfer), "account", "category", "min" (amount); for task_done, event_end and item "text" (words in the title); for item "kind" (task, event, alarm); for habit "habit" (its name); for loan "loanType" ("gave" or "took"); for time "at" (HH:MM) and "days" (1 = Monday ... 7 = Sunday, empty = every day).
  "if" is a list of conditions: {"check": "balance", "account": name, "atLeast": n} or with "below": n; {"check": "spent", "category": name, "period": "day", "week" or "month", "atLeast" or "below": n}; {"check": "days", "days": [1..7]}; {"check": "between", "from": "HH:MM", "to": "HH:MM"}; {"check": "habit_done", "habit": name, "not": true or false}; {"check": "task_open", "text": words, "not": true or false}.
  "then" is a list of actions: {"do": "remind", "text": ...}; {"do": "task", "title": ..., "day": days from now (0 = today), "time": "HH:MM" or null}; {"do": "done", "text": words of the open task to tick off}; {"do": "habit", "habit": name}; {"do": "money", "moneyType": ..., "amount": n or null for the same amount, "account": ..., "category": ..., "note": ...}. Texts may use {amount}, {title}, {account}, {category}, {person}.
  "once" is true when it should happen only the next time ("when I NEXT ...", a one-off purchase), false when it should happen every time ("every time", "whenever").''';

  /// A rule from what an AI wrote, or null with [why] when it cannot be used.
  static (Map<String, dynamic>?, String?) fromAi(Object? raw) {
    if (raw is! Map) return (null, 'no rule given');
    final when = raw['when'];
    if (when is! Map || !triggers.containsKey(when['on'])) return (null, 'unclear what sets it off');
    final then = [for (final a in (raw['then'] as List?) ?? const []) if (a is Map && actions.containsKey(a['do'])) Map<String, dynamic>.from(a)];
    if (then.isEmpty) return (null, 'unclear what to do');
    if (when['on'] == 'time' && _minutes(when['at']) == null) return (null, 'no time given');
    final ifs = [for (final c in (raw['if'] as List?) ?? const []) if (c is Map && checks.containsKey(c['check'])) Map<String, dynamic>.from(c)];
    return (
      {
        'on': true,
        'once': raw['once'] == true,
        'when': {for (final e in when.entries) if (e.value != null) '${e.key}': e.value},
        'if': ifs,
        'then': then,
      },
      null
    );
  }

  /// The built-in links, as rules that start switched off. Turning one on is the person's choice.
  static List<Map<String, dynamic>> builtins() => [
        {
          'builtin': 'rent', 'name': 'Rent goes into Money', 'on': false,
          'when': {'on': 'rent'},
          'then': [{'do': 'money', 'moneyType': 'income', 'account': 'Cash', 'category': 'Rent', 'note': 'Rent room {room}'}],
        },
        {
          'builtin': 'loanGave', 'name': 'Money I lend leaves my account', 'on': false,
          'when': {'on': 'loan', 'loanType': 'gave'},
          'then': [{'do': 'money', 'moneyType': 'expense', 'account': 'Cash', 'category': 'Loan', 'note': 'Lent to {person}'}],
        },
        {
          'builtin': 'loanTook', 'name': 'Money I take comes into my account', 'on': false,
          'when': {'on': 'loan', 'loanType': 'took'},
          'then': [{'do': 'money', 'moneyType': 'income', 'account': 'Cash', 'category': 'Loan', 'note': 'From {person}'}],
        },
        {
          'builtin': 'billDone', 'name': 'Paying a bill ticks off its task', 'on': false,
          'when': {'on': 'money', 'moneyType': 'expense'},
          'then': [{'do': 'done', 'text': '{note}', 'payOnly': true}],
        },
      ];
}
