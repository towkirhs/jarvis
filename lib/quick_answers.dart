/// Everyday questions to Jarvis answered on the phone from your own data, with no AI call:
/// "what do I have tomorrow?", "how much did I spend this week?", "what's my balance?".
/// Pure Dart (takes plain records), so it can be tested on its own.
class QuickAnswers {
  static final _agenda = RegExp(
    r"^(what|what's|whats|anything|show|my)\b.*\b(today|tomorrow|tonight|schedule|agenda)\b",
  );
  static final _spend = RegExp(r"\bhow much\b.*\b(spen[dt]|expenses?)\b");
  static final _balance = RegExp(r"\b(balance|how much (money )?(do i have|is left|have i got|left))\b");
  static final _inAccount = RegExp(r"\b(balance|how much|left|money)\b|\bwhat('?s| is) in\b");
  static final _next = RegExp(r"^(what('?s| is)|when('?s| is)) (my |the )?next( (event|task|thing|meeting|appointment|reminder))?$");
  static final _overdue = RegExp(r"\boverdue\b");
  static final _brief = RegExp(
    r"^(good (morning|afternoon|evening)|(give me )?(my )?(morning |daily )?briefing|brief me)$",
  );
  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  /// Returns the answer, or null if this is not one of these questions (then the AI or the parser takes it).
  static String? answer(
    String raw, {
    required DateTime now,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> tx,
    required Map<String, num> balances,
    required String Function(num) money,
  }) {
    final t = raw
        .trim()
        .toLowerCase()
        .replaceAll('’', "'")
        .replaceAll(RegExp(r'[?.!]+$'), '')
        .replaceFirst(RegExp(r'^(hey |ok |okay )?jarvis[,:]?\s+'), '');
    if (t.split(RegExp(r'\s+')).length > 14) return null;
    if (_brief.hasMatch(t)) return _briefing(t, now, items);
    final question = raw.trim().endsWith('?') ||
        RegExp(r"^(what|how|show|anything|when|whats|what's|my)\b").hasMatch(t);
    if (!question) return null;

    if (_spend.hasMatch(t)) return _spending(t, now, tx, money);
    final account = _inAccount.hasMatch(t) ? _accountIn(t, balances) : null;
    if (account != null) return 'You have ${money(balances[account]!)} in $account.';
    if (_balance.hasMatch(t)) return _balanceText(balances, money);
    if (_next.hasMatch(t)) return _nextText(now, items);
    if (_overdue.hasMatch(t)) return _overdueText(now, items);
    if (_agenda.hasMatch(t)) {
      final tomorrow = t.contains('tomorrow');
      final day = tomorrow ? DateTime(now.year, now.month, now.day + 1) : now;
      return _agendaText(day, now, tomorrow ? 'tomorrow' : 'today', items);
    }
    return null;
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static String _clock(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'am' : 'pm'}';
  }

  /// Open things whose time has passed (an all-day thing is not late until its day is over), oldest first.
  static List<Map<String, dynamic>> _pastDue(DateTime now, List<Map<String, dynamic>> items) => items.where((i) {
        final w = i['when'] as int?;
        if (i['status'] != 'open' || w == null) return false;
        final d = DateTime.fromMillisecondsSinceEpoch(w);
        return d.isBefore(now) && !(i['allDay'] == true && _sameDay(d, now));
      }).toList()
        ..sort((a, b) => (a['when'] as int).compareTo(b['when'] as int));

  static String _overdueText(DateTime now, List<Map<String, dynamic>> items) {
    final behind = _pastDue(now, items);
    if (behind.isEmpty) return 'Nothing overdue.';
    final more = behind.length > 5 ? ', and ${behind.length - 5} more' : '';
    return '${behind.length} overdue: ${behind.take(5).map((i) => i['title']).join(', ')}$more.';
  }

  static String _nextText(DateTime now, List<Map<String, dynamic>> items) {
    final ahead = items.where((i) {
      final w = i['when'] as int?;
      return i['status'] == 'open' && w != null && !DateTime.fromMillisecondsSinceEpoch(w).isBefore(now);
    }).toList()
      ..sort((a, b) => (a['when'] as int).compareTo(b['when'] as int));
    if (ahead.isEmpty) return 'Nothing coming up.';
    final i = ahead.first;
    final d = DateTime.fromMillisecondsSinceEpoch(i['when'] as int);
    final day = _sameDay(d, now)
        ? 'today'
        : _sameDay(d, DateTime(now.year, now.month, now.day + 1))
            ? 'tomorrow'
            : d.difference(now).inDays < 7
                ? 'on ${_days[d.weekday - 1]}'
                : 'on ${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
    return i['allDay'] == true ? 'Next up: ${i['title']}, all day $day.' : 'Next up: ${i['title']} at ${_clock(d)} $day.';
  }

  /// "Good morning": the date and today's plan.
  static String _briefing(String t, DateTime now, List<Map<String, dynamic>> items) {
    final greeting = t.startsWith('good ')
        ? 'Good ${t.split(' ')[1]}'
        : now.hour < 12
            ? 'Good morning'
            : now.hour < 17
                ? 'Good afternoon'
                : 'Good evening';
    return '$greeting. ${_days[now.weekday - 1]} ${now.day} ${_months[now.month - 1]}. '
        '${_agendaText(now, now, 'today', items)}';
  }

  /// The account a question names ("how much cash do I have"), if any.
  static String? _accountIn(String t, Map<String, num> balances) {
    for (final name in balances.keys) {
      if (RegExp('\\b${RegExp.escape(name.toLowerCase())}\\b').hasMatch(t)) return name;
    }
    return null;
  }

  static String _agendaText(DateTime day, DateTime now, String label, List<Map<String, dynamic>> items) {
    final on = items.where((i) {
      final w = i['when'] as int?;
      if (i['status'] != 'open' || w == null) return false;
      final d = DateTime.fromMillisecondsSinceEpoch(w);
      // For today, only what is still ahead (plus all-day things).
      return _sameDay(d, day) && (label != 'today' || i['allDay'] == true || !d.isBefore(now));
    }).toList()
      ..sort((a, b) => (a['when'] as int).compareTo(b['when'] as int));
    final overdue = label == 'today' ? _pastDue(now, items).length : 0;
    final tail = overdue == 0 ? '' : ' Also $overdue overdue.';
    if (on.isEmpty) return 'Nothing planned for $label.$tail';
    final parts = [
      for (final i in on.take(6))
        i['allDay'] == true
            ? '${i['title']}'
            : '${i['title']} at ${_clock(DateTime.fromMillisecondsSinceEpoch(i['when'] as int))}',
    ];
    final more = on.length > 6 ? ', and ${on.length - 6} more' : '';
    return '${on.length} for $label: ${parts.join(', ')}$more.$tail';
  }

  static String _spending(String t, DateTime now, List<Map<String, dynamic>> tx, String Function(num) money) {
    final today = DateTime(now.year, now.month, now.day);
    late final DateTime from;
    late final DateTime to;
    late final String label;
    if (t.contains('yesterday')) {
      from = today.subtract(const Duration(days: 1));
      to = today;
      label = 'yesterday';
    } else if (t.contains('week')) {
      from = today.subtract(Duration(days: now.weekday - 1));
      to = today.add(const Duration(days: 1));
      label = 'this week';
    } else if (t.contains('today')) {
      from = today;
      to = today.add(const Duration(days: 1));
      label = 'today';
    } else {
      from = DateTime(now.year, now.month);
      to = DateTime(now.year, now.month + 1);
      label = 'this month';
    }
    final spent = tx.where((x) {
      final d = DateTime.fromMillisecondsSinceEpoch(x['ts'] as int);
      return x['type'] == 'expense' && !d.isBefore(from) && d.isBefore(to);
    }).toList();
    // "on food", "for transport": narrow to a category the person has used.
    String catOf(Map<String, dynamic> x) => (x['cat'] as String?) ?? 'Other';
    final categories = {for (final x in spent) catOf(x).toLowerCase(): catOf(x)};
    String? cat;
    for (final c in categories.keys) {
      if (RegExp('\\b${RegExp.escape(c)}\\b').hasMatch(t)) cat = categories[c];
    }
    final picked = cat == null ? spent : spent.where((x) => catOf(x) == cat).toList();
    final total = picked.fold<num>(0, (a, x) => a + (x['amount'] as num));
    if (picked.isEmpty) return 'Nothing spent${cat == null ? '' : ' on $cat'} $label.';
    if (cat != null) return 'You spent ${money(total)} on $cat $label.';
    final byCat = <String, num>{};
    for (final x in picked) {
      byCat[catOf(x)] = (byCat[catOf(x)] ?? 0) + (x['amount'] as num);
    }
    final top = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return 'You spent ${money(total)} $label. Most on ${top.take(3).map((e) => '${e.key} ${money(e.value)}').join(', ')}.';
  }

  static String _balanceText(Map<String, num> balances, String Function(num) money) {
    if (balances.isEmpty) return 'You have no money accounts yet.';
    final total = balances.values.fold<num>(0, (a, b) => a + b);
    return 'You have ${money(total)} in total: '
        '${balances.entries.map((e) => '${e.key} ${money(e.value)}').join(', ')}.';
  }
}
