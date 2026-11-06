/// Everyday questions to Jarvis answered on the phone from your own data, with no AI call:
/// "what do I have tomorrow?", "how much did I spend this week?", "what's my balance?".
/// Pure Dart (takes plain records), so it can be tested on its own.
class QuickAnswers {
  static final _agenda = RegExp(
    r"^(what|what's|whats|anything|show|my)\b.*\b(today|tomorrow|tonight|schedule|agenda)\b",
  );
  static final _spend = RegExp(r"\bhow much\b.*\b(spen[dt]|expenses?)\b");
  static final _balance = RegExp(r"\b(balance|how much (money )?(do i have|is left|have i got|left))\b");

  /// Returns the answer, or null if this is not one of these questions (then the AI or the parser takes it).
  static String? answer(
    String raw, {
    required DateTime now,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> tx,
    required Map<String, num> balances,
    required String Function(num) money,
  }) {
    final t = raw.trim().toLowerCase().replaceAll('’', "'").replaceAll(RegExp(r'[?.!]+$'), '');
    if (t.split(RegExp(r'\s+')).length > 14) return null;
    final question = raw.trim().endsWith('?') ||
        RegExp(r"^(what|how|show|anything|when|whats|what's|my)\b").hasMatch(t);
    if (!question) return null;

    if (_spend.hasMatch(t)) return _spending(t, now, tx, money);
    if (_balance.hasMatch(t)) return _balanceText(balances, money);
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

  static String _agendaText(DateTime day, DateTime now, String label, List<Map<String, dynamic>> items) {
    final on = items.where((i) {
      final w = i['when'] as int?;
      if (i['status'] != 'open' || w == null) return false;
      final d = DateTime.fromMillisecondsSinceEpoch(w);
      // For today, only what is still ahead (plus all-day things).
      return _sameDay(d, day) && (label != 'today' || i['allDay'] == true || !d.isBefore(now));
    }).toList()
      ..sort((a, b) => (a['when'] as int).compareTo(b['when'] as int));
    final overdue = label == 'today'
        ? items.where((i) {
            final w = i['when'] as int?;
            return i['status'] == 'open' &&
                w != null &&
                DateTime.fromMillisecondsSinceEpoch(w).isBefore(now) &&
                !(i['allDay'] == true && _sameDay(DateTime.fromMillisecondsSinceEpoch(w), now));
          }).length
        : 0;
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
    final categories = {for (final x in spent) (x['category'] as String).toLowerCase(): x['category'] as String};
    String? cat;
    for (final c in categories.keys) {
      if (RegExp('\\b${RegExp.escape(c)}\\b').hasMatch(t)) cat = categories[c];
    }
    final picked = cat == null ? spent : spent.where((x) => x['category'] == cat).toList();
    final total = picked.fold<num>(0, (a, x) => a + (x['amount'] as num));
    if (picked.isEmpty) return 'Nothing spent${cat == null ? '' : ' on $cat'} $label.';
    if (cat != null) return 'You spent ${money(total)} on $cat $label.';
    final byCat = <String, num>{};
    for (final x in picked) {
      byCat[x['category'] as String] = (byCat[x['category']] ?? 0) + (x['amount'] as num);
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
