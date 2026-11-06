/// Understands simple, single-command notes on the phone, with no AI call:
/// alarms, timed tasks and events, money, habit check-ins, moving an item, and birthdays.
/// Returns the same shape the AI returns ({cleaned, topics, items}), or null when the note is not
/// clearly simple, in which case it goes to the AI as before. Pure Dart, so it can be tested on its own.
class LocalParser {
  static const _months = {
    'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3, 'apr': 4, 'april': 4,
    'may': 5, 'jun': 6, 'june': 6, 'jul': 7, 'july': 7, 'aug': 8, 'august': 8, 'sep': 9, 'sept': 9,
    'september': 9, 'oct': 10, 'october': 10, 'nov': 11, 'november': 11, 'dec': 12, 'december': 12,
  };
  static const _weekdays = {
    'monday': 1, 'mon': 1, 'tuesday': 2, 'tue': 2, 'wednesday': 3, 'wed': 3, 'thursday': 4, 'thu': 4,
    'friday': 5, 'fri': 5, 'saturday': 6, 'sat': 6, 'sunday': 7, 'sun': 7,
  };
  static const _eventWords = [
    'meeting', 'class', 'tuition', 'appointment', 'exam', 'party', 'interview', 'lecture', 'lab',
    'dinner with', 'lunch with', 'wedding', 'match', 'flight', 'bus to', 'train to', 'dentist', 'doctor',
  ];
  static const _expenseWords = ['spent', 'spend', 'paid', 'pay ', 'bought', 'cost', 'khoroch', 'kinlam', 'kinechi', 'expense'];
  static const _incomeWords = ['received', 'got paid', 'salary', 'earned', 'income', 'pelam', 'peyechi', 'got '];
  static const _categories = {
    'Food': ['lunch', 'dinner', 'breakfast', 'food', 'khabar', 'snack', 'tea', 'coffee', 'restaurant', 'biryani', 'pizza', 'burger', 'grocer'],
    'Transport': ['rickshaw', 'bus', 'uber', 'pathao', 'cng', 'fare', 'transport', 'train', 'taxi', 'fuel', 'petrol'],
    'Bills': ['bill', 'electricity', 'internet', 'wifi', 'rent', 'gas', 'recharge'],
    'Health': ['medicine', 'doctor', 'hospital', 'pharmacy', 'medical'],
    'Education': ['book', 'course', 'exam fee', 'admission', 'stationery', 'photocopy'],
    'Entertainment': ['movie', 'netflix', 'game', 'concert', 'spotify'],
    'Gifts': ['gift'],
    'Shopping': ['shirt', 'shoes', 'clothes', 'shopping', 'dress', 'bag', 'watch', 'phone', 'panjabi'],
    'Salary': ['salary'],
    'Tuition': ['tuition'],
  };

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _day(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
  static bool _hasWord(String text, String w) => RegExp('(^|[^a-z])${RegExp.escape(w)}([^a-z]|\$)').hasMatch(text);

  /// A time like "4:30 pm", "4.30", "4 pm", "at 7", "7 tay", "sokal 7". Returns (hour, minute, matched text).
  static (int, int, String)? _time(String t, {required bool morningDefault}) {
    final m = RegExp(
      r'(?:(sokal|bikal|bikel|sondha|sondhay|rat|raat|morning|evening|night|afternoon)\s+)?'
      r'(?:\b(?:at|by|@)\s+)?'
      r'\b(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.|tay|te|e)?\b'
      r'(?:\s+(sokal|bikal|bikel|sondha|sondhay|rat|raat|in the morning|in the evening|at night))?',
    ).allMatches(t).where((m) {
      // A bare number is only a time with "at", a colon or dot, am/pm, or a Bangla time word.
      final s = m.group(0)!;
      return m.group(3) != null || m.group(4) != null || m.group(1) != null || m.group(5) != null || s.contains(RegExp(r'\b(at|by|@)\s'));
    }).toList();
    if (m.length != 1) return null;
    final g = m.single;
    var h = int.parse(g.group(2)!);
    final min = int.tryParse(g.group(3) ?? '') ?? 0;
    if (h > 23 || min > 59) return null;
    final ampm = (g.group(4) ?? '').replaceAll('.', '');
    final part = '${g.group(1) ?? ''} ${g.group(5) ?? ''}';
    final pm = ampm == 'pm' || RegExp(r'bikal|bikel|sondha|rat|raat|evening|night|afternoon').hasMatch(part);
    final am = ampm == 'am' || RegExp(r'sokal|morning').hasMatch(part);
    if (pm && h < 12) h += 12;
    if (am && h == 12) h = 0;
    // No am/pm said: alarms are mornings; plans at 1-7 o'clock are afternoons.
    if (!pm && !am && h <= 12 && !morningDefault && h >= 1 && h <= 7) h += 12;
    return (h, min, g.group(0)!);
  }

  /// A date like "today", "kal", "tomorrow", "porshu", "friday", "on 12 march", "march 12", "in 2 days".
  static (DateTime, String)? _date(String t, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    DateTime plus(int d) => DateTime(today.year, today.month, today.day + d);
    final rules = <(RegExp, DateTime Function(Match))>[
      (RegExp(r'\b(day after tomorrow|porshu|porshudin)\b'), (_) => plus(2)),
      (RegExp(r'\b(tomorrow|tmrw|kal|kalke|agamikal)\b'), (_) => plus(1)),
      (RegExp(r'\b(today|tonight|aj|aaj|ajke|aajke)\b'), (_) => today),
      (RegExp(r'\b(yesterday|gotokal)\b'), (_) => plus(-1)),
      (RegExp(r'\bin (\d{1,2}) days?\b'), (m) => plus(int.parse(m.group(1)!))),
      (
        RegExp(r'\b(?:on |next |this )?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b'),
        (m) {
          final wd = _weekdays[m.group(1)!]!;
          var diff = (wd - today.weekday) % 7;
          if (diff == 0) diff = 7;
          return plus(diff);
        }
      ),
      (
        RegExp(r'\b(?:on )?(\d{1,2})(?:st|nd|rd|th)?\s+(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\b'),
        (m) => _future(today, _months[m.group(2)!]!, int.parse(m.group(1)!))
      ),
      (
        RegExp(r'\b(?:on )?(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)\s+(\d{1,2})(?:st|nd|rd|th)?\b'),
        (m) => _future(today, _months[m.group(1)!]!, int.parse(m.group(2)!))
      ),
    ];
    (DateTime, String)? found;
    for (final (re, f) in rules) {
      final all = re.allMatches(t).toList();
      if (all.isEmpty) continue;
      if (found != null || all.length > 1) return null; // two dates: not a simple note
      found = (f(all.single), all.single.group(0)!);
    }
    return found;
  }

  /// The next time this month and day comes round (this year, or next year if it has passed).
  static DateTime _future(DateTime today, int month, int day) {
    final d = DateTime(today.year, month, day);
    return d.isBefore(today) ? DateTime(today.year + 1, month, day) : d;
  }

  /// Removes the time and date words and fillers, leaving the title.
  static String _title(String text, List<String> remove) {
    var t = ' $text ';
    for (final r in remove) {
      if (r.isNotEmpty) t = t.replaceFirst(RegExp(RegExp.escape(r), caseSensitive: false), ' ');
    }
    t = t.replaceAll(
      RegExp(
        r"\b(please|remind me to|remind me|don't forget to|dont forget to|i need to|i have to|i must|i should|i will|i'll|need to|have to|add a task to|add task|add|set a reminder to|reminder to|reminder)\b",
        caseSensitive: false,
      ),
      ' ',
    );
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceAll(RegExp(r'^(to|at|on|by|for|e|te|ase|ache|is|for the)\s+', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\s+(at|on|by|e|te|ase|ache|is|for|from)$', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'^[\s,.\-]+|[\s,.\-]+$'), '');
    if (t.isEmpty) return '';
    return t[0].toUpperCase() + t.substring(1);
  }

  static Map<String, dynamic> _result(String raw, Map<String, dynamic> item) => {
        'cleaned': raw,
        'topics': <String>[],
        'items': [
          {'confidence': 0.9, ...item},
        ],
      };

  static Map<String, dynamic>? parse(
    String raw, {
    required DateTime now,
    List<String> habits = const [],
    List<String> accounts = const [],
  }) {
    final text = raw.trim();
    final t = text.toLowerCase().replaceAll('’', "'");
    final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    // Long notes, several sentences or several actions are left to the AI.
    if (words == 0 || words > 22 || text.contains('\n')) return null;
    if (RegExp(r'[.!?]\s+\S').hasMatch(text)) return null;
    if (RegExp(r'\b(and then|also|then|after that|tar por|tarpor)\b').hasMatch(t)) return null;

    return _money(text, t, now, accounts) ??
        _habit(text, t, now, habits) ??
        _done(text, t) ??
        _birthday(text, t, now) ??
        _move(text, t, now) ??
        _alarm(text, t, now) ??
        _timed(text, t, now);
  }

  static Map<String, dynamic>? _money(String text, String t, DateTime now, List<String> accounts) {
    final expense = _expenseWords.any(t.contains);
    final income = !expense && _incomeWords.any(t.contains) && !t.contains('got to');
    final currency = RegExp(r'(\btk\b|\btaka\b|৳|\bbdt\b|/-)').hasMatch(t);
    if (!expense && !income && !currency) return null;
    // Take out the time first, so "at 2pm" is not read as an amount.
    final time = _time(t, morningDefault: false);
    final rest = time == null ? t : t.replaceFirst(time.$3, ' ');
    final amounts = RegExp(r'(?:৳\s*)?\b(\d[\d,]*(?:\.\d+)?)\s*(?:tk|taka|৳|bdt|/-|k\b)?').allMatches(rest).toList();
    if (amounts.length != 1) return null;
    var amount = num.parse(amounts.single.group(1)!.replaceAll(',', ''));
    if (RegExp(r'\d\s*k\b').hasMatch(amounts.single.group(0)!)) amount *= 1000;
    if (amount <= 0) return null;
    var category = income ? 'Other' : 'Other';
    for (final e in _categories.entries) {
      if (e.value.any((w) => RegExp('(^|[^a-z])${RegExp.escape(w)}').hasMatch(t))) {
        category = e.key;
        break;
      }
    }
    if (income && !['Salary', 'Tuition', 'Gifts'].contains(category)) category = 'Other';
    if (income && category == 'Gifts') category = 'Gift';
    String? account;
    for (final a in accounts) {
      if (_hasWord(t, a.toLowerCase())) account = a;
    }
    final date = _date(t, now);
    final note = RegExp(r'\b(?:on|for)\s+([a-z][a-z ]{1,30}?)(?:\s+(?:with|from|by|using|via|today|yesterday|tk|taka)\b|$)')
        .firstMatch(t)
        ?.group(1)
        ?.trim();
    final title = note == null || note.isEmpty ? category : note[0].toUpperCase() + note.substring(1);
    return _result(text, {
      'type': 'money',
      'moneyType': income ? 'income' : 'expense',
      'amount': amount,
      'title': title,
      'category': category,
      'account': account,
      'date': date == null ? null : _day(date.$1),
      'time': null,
    });
  }

  /// "finished the lab report", "done call ammu": marks an open item done (Brain checks it matches one).
  static Map<String, dynamic>? _done(String text, String t) {
    final m = RegExp(
      r"^(?:i(?:\s+have|'ve)?\s+)?(?:done|finished|completed|submitted|sent|did)\s+(?:with\s+)?(?:the\s+|my\s+)?(.+?)[.!]?$",
    ).firstMatch(t);
    if (m == null || m.group(1)!.split(' ').length > 8) return null;
    return _result(text, {'type': 'complete', 'target': m.group(1)});
  }

  static Map<String, dynamic>? _habit(String text, String t, DateTime now, List<String> habits) {
    final skipped = RegExp(r"\b(skipped|missed|didn't|did not|couldn't|could not|no |hoy nai|hoyni|kori nai|korini|jaini|jai nai)\b").hasMatch(t);
    final did = RegExp(r'\b(did|done|went|finished|completed|had my|korsi|korechi|kora hoise|gelam|gechi|gesilam)\b').hasMatch(t);
    if (!skipped && !did) return null;
    final matches = habits.where((h) => _hasWord(t, h.toLowerCase())).toList();
    if (matches.length != 1) return null;
    final yesterday = RegExp(r'\b(yesterday|gotokal)\b').hasMatch(t);
    final day = yesterday ? DateTime(now.year, now.month, now.day - 1) : now;
    return _result(text, {
      'type': 'habit_log',
      'habit': matches.single,
      'title': matches.single,
      'done': !skipped,
      'date': _day(day),
    });
  }

  static Map<String, dynamic>? _birthday(String text, String t, DateTime now) {
    final m = RegExp(r"^(.+?)(?:'s)?\s+(birthday|anniversary)\b").firstMatch(t);
    if (m == null) return null;
    final date = _date(t, now);
    if (date == null) return null;
    final who = text.substring(0, m.group(1)!.length).trim();
    final kind = m.group(2)!;
    final mine = ['my', 'our'].contains(who.toLowerCase());
    return _result(text, {
      'type': 'countdown',
      'category': kind,
      'title': mine ? '${who[0].toUpperCase()}${who.substring(1).toLowerCase()} $kind' : "$who's $kind",
      'date': _day(date.$1),
    });
  }

  static Map<String, dynamic>? _move(String text, String t, DateTime now) {
    final m = RegExp(r'^(?:please\s+)?(move|push|postpone|shift|delay|reschedule)\s+(?:the\s+|my\s+)?(.+?)\s+(?:to|till|until)\s+(.+)$').firstMatch(t);
    if (m == null) return null;
    final rest = m.group(3)!;
    final time = _time(rest, morningDefault: false);
    final date = _date(rest, now);
    if (time == null && date == null) return null;
    return _result(text, {
      'type': 'delay',
      'target': m.group(2)!.trim(),
      'title': m.group(2)!.trim(),
      'date': date == null ? null : _day(date.$1),
      'time': time == null ? null : '${_two(time.$1)}:${_two(time.$2)}',
    });
  }

  static Map<String, dynamic>? _alarm(String text, String t, DateTime now) {
    if (!RegExp(r'\b(alarm|wake me|wake up|uthiye dio|uthaiyo)\b').hasMatch(t)) return null;
    final time = _time(t, morningDefault: true);
    if (time == null) return null;
    final date = _date(t, now);
    final name = _title(text, [time.$3, if (date != null) date.$2])
        .replaceAll(RegExp(r'^(set (an |the )?)?(alarm|wake me up|wake me|wake up)\b\s*(for|to)?\s*', caseSensitive: false), '')
        .trim();
    return _result(text, {
      'type': 'alarm',
      'title': name.isEmpty ? (t.contains('wake') ? 'Wake up' : 'Alarm') : name[0].toUpperCase() + name.substring(1),
      'date': date == null ? null : _day(date.$1),
      'time': '${_two(time.$1)}:${_two(time.$2)}',
    });
  }

  static Map<String, dynamic>? _timed(String text, String t, DateTime now) {
    // Telling about the day ("I woke up at 7 feeling great") is journal, not a plan: leave it to the AI.
    if (RegExp(r"\b(i was|i felt|i feel|feeling|i woke|i went|i had|i did|was|were|got|today was)\b").hasMatch(t)) return null;
    final time = _time(t, morningDefault: false);
    final date = _date(t, now);
    if (time == null && date == null) return null;
    final title = _title(text, [if (time != null) time.$3, if (date != null) date.$2]);
    if (title.isEmpty || title.split(' ').length > 10) return null;
    final event = _eventWords.any((w) => t.contains(w)) && !t.contains('remind');
    final due = date?.$1 ?? DateTime(now.year, now.month, now.day);
    return _result(text, {
      'type': event ? 'event' : 'task',
      'title': title,
      'date': date == null && time != null ? null : _day(due),
      'time': time == null ? null : '${_two(time.$1)}:${_two(time.$2)}',
    });
  }
}
