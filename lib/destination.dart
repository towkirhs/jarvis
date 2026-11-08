/// Where you said a note should go: "calendar: dinner with Oishi Friday 8pm", "task: buy milk",
/// "journal: today was good", "add to my calendar …", "… to my tasks".
/// [type] is the item type Jarvis must make ('event', 'task', 'alarm', or 'note' for the journal);
/// [rest] is the note without the destination words.
class Destination {
  const Destination(this.type, this.rest);
  final String type;
  final String rest;

  /// Words that can start a note, with or without a colon after them.
  static const _lead = {
    'calendar': 'event',
    'event': 'event',
    'task': 'task',
    'todo': 'task',
    'to-do': 'task',
    'alarm': 'alarm',
    'journal': 'note',
    'diary': 'note',
  };

  /// "my calendar", "my tasks" after "add to / put in / save in", at the start or the end.
  static const _place = {
    'calendar': 'event',
    'events': 'event',
    'tasks': 'task',
    'task list': 'task',
    'to-do list': 'task',
    'todo list': 'task',
    'to do list': 'task',
    'to-dos': 'task',
    'todos': 'task',
    'alarms': 'alarm',
    'journal': 'note',
    'diary': 'note',
  };

  static String _alt(Iterable<String> words) =>
      (words.toList()..sort((a, b) => b.length - a.length)).map(RegExp.escape).join('|');

  static final _leadRe = RegExp('^(${_alt(_lead.keys)})\\b\\s*[:,\\-–]?\\s*', caseSensitive: false);
  // "note:" only with a colon, since "note that …" is ordinary speech.
  static final _noteRe = RegExp(r'^note\s*:\s*', caseSensitive: false);
  static final _addRe = RegExp(
      '^(?:add|put|save|write)(?: (?:this|it))? (?:to|in|into|on) (?:my |the )?(${_alt(_place.keys)})\\b\\s*[:,\\-–]?\\s*',
      caseSensitive: false);
  static final _tailRe = RegExp(
      '[,.]?\\s+(?:(?:add|put|save|write)(?: (?:it|this))? )?(?:to|in|into|on) (?:my |the )?(${_alt(_place.keys)})[.!]?\$',
      caseSensitive: false);

  static Destination? of(String raw) {
    final t = raw.trim();
    Destination? make(String type, String rest) {
      final r = rest.trim();
      return r.isEmpty ? null : Destination(type, r);
    }

    var m = _addRe.firstMatch(t);
    if (m != null) return make(_place[m[1]!.toLowerCase()]!, t.substring(m.end));
    m = _noteRe.firstMatch(t);
    if (m != null) return make('note', t.substring(m.end));
    m = _leadRe.firstMatch(t);
    if (m != null) return make(_lead[m[1]!.toLowerCase()]!, t.substring(m.end));
    m = _tailRe.firstMatch(t);
    if (m != null) return make(_place[m[1]!.toLowerCase()]!, t.substring(0, m.start));
    return null;
  }

  /// Makes parsed items (from the phone or the AI) go where you said: tasks, events and alarms become [type],
  /// and if nothing of that kind is left, one is made from the note itself.
  static Map<String, dynamic> force(Map<String, dynamic> data, Destination d) {
    const timed = {'task', 'event', 'alarm'};
    final items = [
      for (final raw in ((data['items'] as List?) ?? const []))
        if (!const {'note', 'ignore'}.contains((raw as Map)['type']))
          timed.contains(raw['type']) ? {...Map<String, dynamic>.from(raw), 'type': d.type} : Map<String, dynamic>.from(raw),
    ];
    if (!items.any((i) => i['type'] == d.type)) items.add({'type': d.type, 'title': d.rest, 'confidence': 1});
    return {...data, 'items': items};
  }

  static const names = {'event': 'calendar', 'task': 'tasks', 'alarm': 'alarms', 'note': 'journal'};
}
