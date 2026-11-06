import 'dart:convert';
import 'dart:math';

/// Typed decisions, in the spirit of Jev AI: give Jarvis a situation and typed questions, get back answers with
/// probabilities that code can act on — no chat. Three kinds of question:
///  * choice: pick one of the options (or, when none are given, the AI names up to 4),
///  * score: a rating on a scale, like 1 to 5,
///  * yesno: the chance the answer is yes.
/// Everything here except [Decide.prompt] is pure Dart and tested.
class Question {
  const Question.choice(this.id, this.text, [this.options = const []])
      : type = 'choice',
        low = 0,
        high = 0;
  const Question.score(this.id, this.text, {this.low = 1, this.high = 5})
      : type = 'score',
        options = const [];
  const Question.yesno(this.id, this.text)
      : type = 'yesno',
        options = const [],
        low = 0,
        high = 0;

  final String id;
  final String type;
  final String text;
  final List<String> options;
  final int low;
  final int high;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'question': text,
        if (type == 'choice') 'options': options.isEmpty ? 'name 2 to 4 sensible options yourself' : options,
        if (type == 'score') 'scale': '$low to $high',
      };
}

class Answer {
  Answer({required this.id, required this.type, required this.probs});

  final String id;
  final String type;

  /// Option (or score value as text, or 'yes'/'no') to probability. Always sums to 1, highest first.
  final Map<String, double> probs;

  /// The picked option, score value, or 'yes'/'no'.
  String get pick => probs.keys.first;

  /// How sure: the probability of the pick.
  double get confidence => probs.values.first;

  /// For a score: the probability-weighted value. For yes/no: the chance of yes.
  double get value => type == 'score'
      ? probs.entries.fold(0.0, (a, e) => a + (double.tryParse(e.key) ?? 0) * e.value)
      : (probs['yes'] ?? 0);

  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'probs': probs};
}

class Decide {
  /// The instruction sent to the AI. [state] is everything it should decide from.
  static String prompt(String state, List<Question> questions) => '''You are a decision model, not a chatbot. Read the state and answer each typed question with probabilities. No explanations.
Return ONLY JSON: {"answers": [{"id": string, "probs": {option: probability}}]}
- choice: one probability per option (use the given options exactly; if none are given, name 2 to 4 short options yourself).
- score: one probability per whole number on the scale, keys like "1", "2".
- yesno: keys "yes" and "no".
Probabilities are 0 to 1 and sum to 1 for each question. Be decisive when the state supports it, and spread the probability when it truly does not.

Questions: ${jsonEncode(questions.map((q) => q.toJson()).toList())}

State:
$state''';

  /// Reads the AI's answer and makes it safe to act on: unknown options dropped, probabilities clamped and
  /// normalised, missing questions given an even spread (so confidence is low and nothing acts on its own).
  static List<Answer> parse(String text, List<Question> questions) {
    var t = text.trim();
    if (t.startsWith('```')) t = t.replaceFirst(RegExp(r'^```[a-zA-Z]*'), '').replaceFirst(RegExp(r'```\s*$'), '').trim();
    Map<String, dynamic> raw = {};
    try {
      final decoded = jsonDecode(t);
      final list = decoded is Map ? decoded['answers'] : decoded;
      for (final a in (list as List? ?? const [])) {
        if (a is Map && a['id'] != null && a['probs'] is Map) raw[a['id'].toString()] = a['probs'];
      }
    } catch (_) {
      // Unreadable: every question falls back to an even spread below.
    }
    return [for (final q in questions) _answer(q, (raw[q.id] as Map?)?.cast<String, dynamic>() ?? const {})];
  }

  static Answer _answer(Question q, Map<String, dynamic> given) {
    final allowed = switch (q.type) {
      'yesno' => ['yes', 'no'],
      'score' => [for (var v = q.low; v <= q.high; v++) '$v'],
      _ => q.options,
    };
    final probs = <String, double>{};
    if (allowed.isEmpty) {
      // A choice the AI named itself: take its options as given, at most 4.
      for (final e in given.entries.take(4)) {
        final key = e.key.trim();
        if (key.isNotEmpty) probs[key] = _num(e.value);
      }
    } else {
      for (final key in allowed) {
        final match = given.entries.where((e) => e.key.trim().toLowerCase() == key.toLowerCase());
        probs[key] = match.isEmpty ? 0 : _num(match.first.value);
      }
    }
    return Answer(id: q.id, type: q.type, probs: _normalise(probs, allowed));
  }

  static double _num(Object? v) => v is num ? v.toDouble().clamp(0.0, 1.0) : (double.tryParse('$v') ?? 0).clamp(0.0, 1.0);

  static Map<String, double> _normalise(Map<String, double> probs, List<String> allowed) {
    final keys = probs.isEmpty ? allowed : probs.keys.toList();
    if (keys.isEmpty) return {'unknown': 1};
    final total = probs.values.fold(0.0, (a, b) => a + b);
    final out = {
      for (final k in keys) k: total <= 0 ? 1 / keys.length : (probs[k] ?? 0) / total,
    };
    final sorted = out.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
  }

  /// Is this note asking Jarvis to decide? ("should I…", "X or Y?", "decide…", "which one…")
  static bool isDecisionRequest(String note) {
    final t = note.trim().toLowerCase();
    return RegExp(r'^(jarvis,?\s+)?(should i|shall i|do i|is it worth|which (one|should)|decide|help me decide|pick)\b').hasMatch(t) ||
        (t.endsWith('?') && RegExp(r'\S\s+or\s+\S').hasMatch(t));
  }

  /// "What should I do now?" decided on the phone from your own tasks: a choice with probabilities.
  /// Favours overdue, due-soon and high-priority tasks, and ones that fit before your next fixed event.
  static Answer whatNow(List<Map<String, dynamic>> items, DateTime now) {
    final nowMs = now.millisecondsSinceEpoch;
    final endOfDay = DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
    final nextFixed = items
        .where((i) => i['status'] == 'open' && i['kind'] != 'task' && i['allDay'] != true)
        .map((i) => i['when'] as int?)
        .whereType<int>()
        .where((w) => w > nowMs)
        .fold<int?>(null, (a, w) => a == null || w < a ? w : a);
    final freeMinutes = nextFixed == null ? 24 * 60 : (nextFixed - nowMs) ~/ 60000;

    final scores = <String, double>{};
    for (final i in items) {
      if (i['status'] != 'open' || i['kind'] != 'task') continue;
      final w = i['when'] as int?;
      if (w != null && w >= endOfDay) continue; // later this week: not now
      var score = ((i['priority'] as int?) ?? 0).toDouble();
      if (w != null && w < nowMs) score += 2; // overdue
      if (w != null && w >= nowMs) score += w - nowMs < 3 * 3600000 ? 1.5 : 1; // due today, sooner is stronger
      final est = (i['est'] as int?) ?? 30;
      score += est <= freeMinutes ? 0.5 : -1;
      score += min(((i['postponed'] as int?) ?? 0) * 0.3, 1.2); // kept putting it off
      scores['${i['id']}'] = score;
    }
    if (scores.isEmpty) return Answer(id: 'now', type: 'choice', probs: {'nothing': 1});
    // Softmax: higher scores get most of the probability, close scores share it.
    final top = scores.values.reduce(max);
    final weights = {for (final e in scores.entries) e.key: exp((e.value - top) * 1.2)};
    return Answer(id: 'now', type: 'choice', probs: _normalise(weights, const []));
  }
}
