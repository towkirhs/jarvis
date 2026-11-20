import 'dart:convert';

/// One part of Jarvis that can be copied or saved on its own and added to another Jarvis.
class Section {
  const Section(this.key, this.name, this.cols);
  final String key;
  final String name;

  /// The collections it holds (money is entries and accounts together).
  final List<String> cols;
}

/// Taking one section out (as text or a file) and putting it into a Jarvis, next to what is there.
class Sections {
  static const all = [
    Section('items', 'Tasks and events', ['items']),
    Section('habits', 'Habits', ['habits']),
    Section('money', 'Money', ['accounts', 'tx', 'goals']),
    Section('journal', 'Journal', ['entries']),
    Section('countdowns', 'Countdowns', ['countdowns']),
    Section('promises', 'Promises', ['promises']),
    Section('decisions', 'Decisions', ['decisions']),
    Section('rules', 'Rules and links', ['rules']),
    Section('rent', 'Rent', ['rooms', 'rentPays', 'roomBills', 'houseCosts']),
    Section('loans', 'Loans and debts', ['loanPeople', 'loans']),
    Section('income', 'Income', ['incomes', 'incomePays']),
    Section('memory', 'Memory and About me', ['memories', 'words', 'profile']),
    Section('clock', 'Alarms and places', ['clocks', 'places', 'appAlarms']),
    Section('cards', 'Flashcards', ['cards']),
    Section('day', 'Your day', ['log', 'acts']),
    Section('media', 'Movies and books', ['media']),
  ];

  static Section? byKey(String key) => all.where((x) => x.key == key).firstOrNull;

  /// How many records [sec] has in [state].
  static int count(Map<String, dynamic> state, Section sec) =>
      sec.cols.fold(0, (n, c) => n + ((state[c] as List?)?.length ?? 0));

  /// [sec] as text: {"jarvisSection": key, "data": {collection: [records]}}.
  static String export(Map<String, dynamic> state, Section sec) => const JsonEncoder.withIndent(' ').convert({
        'jarvisSection': sec.key,
        'data': {for (final c in sec.cols) c: state[c] ?? []},
      });

  /// Reads section text: (section, its data), or a FormatException.
  static (Section, Map<String, List<Map<String, dynamic>>>) parse(String text) {
    final j = jsonDecode(text);
    final sec = j is Map ? byKey('${j['jarvisSection']}') : null;
    if (sec == null || j['data'] is! Map) throw const FormatException('Not a Jarvis section');
    final data = <String, List<Map<String, dynamic>>>{};
    for (final c in sec.cols) {
      final list = (j['data'] as Map)[c];
      if (list is List) data[c] = [for (final r in list) if (r is Map) Map<String, dynamic>.from(r)];
    }
    return (sec, data);
  }

  /// A record's content, without the fields that only say where it lives (ids, reminder ids, sync stamps).
  static String _content(Map r) {
    final copy = Map.of(r)..removeWhere((k, _) => const {'id', 'nid', 'rid', '_t'}.contains(k));
    final keys = copy.keys.map((k) => '$k').toList()..sort();
    return jsonEncode({for (final k in keys) k: copy[k]});
  }

  /// Adds [data]'s records to [state] with new ids, skipping ones already there (same content).
  /// Accounts are matched by name. [nextId] gives new ids. Returns the added records by collection.
  static Map<String, List<Map<String, dynamic>>> merge(
    Map<String, dynamic> state,
    Map<String, List<Map<String, dynamic>>> data,
    int Function() nextId,
  ) {
    final added = <String, List<Map<String, dynamic>>>{};
    data.forEach((c, recs) {
      final list = (state[c] as List?) ?? (state[c] = <dynamic>[]);
      final have = {for (final r in list) _content(r as Map)};
      final names = {for (final r in list) if (c == 'accounts') '${(r as Map)['name']}'.toLowerCase()};
      for (final r in recs) {
        if (have.contains(_content(r))) continue;
        if (c == 'accounts' && names.contains('${r['name']}'.toLowerCase())) continue;
        final n = Map<String, dynamic>.from(r)
          ..['id'] = nextId()
          ..remove('_t');
        if (r['nid'] != null) n['nid'] = nextId();
        if (r['rid'] != null) n['rid'] = nextId();
        list.add(n);
        have.add(_content(n));
        (added[c] ??= []).add(n);
      }
    });
    return added;
  }
}
