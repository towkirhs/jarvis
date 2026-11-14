/// Links between the pieces of a day: "do B only if A is done", "D only if A is not done",
/// "only if Cash has 500", "only while the exam countdown runs". Pure Dart, so it can be tested on its own.
///
/// A piece is a task (its id) or a habit (minus its id). A piece's `needs` (and `doneIf`) is
/// `{any: bool, if: [check]}`: every check must hold, or with `any` one is enough. Checks:
/// ```
/// {check: done, id: piece, not: bool}          that task or habit is done (not: is not done)
/// {check: balance, account, atLeast | below}   an account's balance
/// {check: countdown, id, not: bool}            the countdown is still running (not: it has ended)
/// ```
abstract class NeedFacts {
  /// 'done'; 'open' (not done, still part of this day); or 'missed' (left out, on another day, gone,
  /// or its time has passed without being done).
  String piece(int id);

  /// Balance of the named account, or null when there is no such account.
  num? balance(String account);

  /// Whether the countdown has not reached its date yet; null when it is gone.
  bool? countdownRunning(int id);
}

enum NeedState {
  /// Nothing in the way: plan it and remind as usual.
  met,

  /// It follows pieces that are still open: plan it after them, remind only once they are done.
  after,

  /// It is the fallback for a piece that is still open: no time and no reminder unless that piece is missed.
  standby,

  /// A condition does not hold: not for this day.
  off,
}

class NeedResult {
  const NeedResult(this.state, {this.after = const [], this.why = ''});
  final NeedState state;

  /// For [NeedState.after]: the pieces it follows.
  final List<int> after;

  /// In words, for the person: "after Gym", "only if Gym is not done", "Cash is under 500".
  final String why;
}

enum _Tri { yes, no, later, standby }

class Needs {
  static const met = NeedResult(NeedState.met);

  static List<Map> checks(Object? needs) =>
      needs is Map ? [for (final c in (needs['if'] as List?) ?? const []) if (c is Map) c] : const [];

  static bool has(Object? needs) => checks(needs).isNotEmpty;

  static _Tri _check(Map c, NeedFacts f) {
    switch (c['check']) {
      case 'done':
        final p = f.piece((c['id'] as num).toInt());
        if (c['not'] == true) return p == 'done' ? _Tri.no : (p == 'open' ? _Tri.standby : _Tri.yes);
        return p == 'done' ? _Tri.yes : (p == 'open' ? _Tri.later : _Tri.no);
      case 'balance':
        final b = f.balance('${c['account'] ?? 'Cash'}');
        if (b == null) return _Tri.no;
        if (c['atLeast'] is num && b < (c['atLeast'] as num)) return _Tri.no;
        if (c['below'] is num && b >= (c['below'] as num)) return _Tri.no;
        return _Tri.yes;
      case 'countdown':
        final r = f.countdownRunning((c['id'] as num).toInt());
        if (r == null) return c['not'] == true ? _Tri.yes : _Tri.no;
        return r != (c['not'] == true) ? _Tri.yes : _Tri.no;
    }
    return _Tri.no;
  }

  /// One check in words. [name] gives a piece's or countdown's title; [money] formats an amount.
  static String sentence(Map c, {required String Function(String kind, int id) name, String Function(num)? money}) {
    String amt(Object? v) => v is num ? (money?.call(v) ?? '$v') : '$v';
    switch (c['check']) {
      case 'done':
        final id = (c['id'] as num).toInt();
        return '${name(id < 0 ? 'habit' : 'task', id.abs())} is ${c['not'] == true ? 'not ' : ''}done';
      case 'balance':
        return '${c['account'] ?? 'Cash'} has ${c['atLeast'] != null ? 'at least ${amt(c['atLeast'])}' : 'under ${amt(c['below'])}'}';
      case 'countdown':
        return '${name('countdown', (c['id'] as num).toInt())} ${c['not'] == true ? 'has ended' : 'is still running'}';
    }
    return '?';
  }

  /// The whole of [needs] in words: "Gym is done and Cash has at least 500".
  static String describe(Object? needs, {required String Function(String kind, int id) name, String Function(num)? money}) =>
      checks(needs).map((c) => sentence(c, name: name, money: money)).join(needs is Map && needs['any'] == true ? ' or ' : ' and ');

  /// Where a piece with [needs] stands on this day.
  static NeedResult state(Object? needs, NeedFacts f, {required String Function(String kind, int id) name, String Function(num)? money}) {
    final list = checks(needs);
    if (list.isEmpty) return met;
    final any = (needs as Map)['any'] == true;
    final tris = [for (final c in list) _check(c, f)];
    String words(_Tri t) => [
          for (var k = 0; k < list.length; k++)
            if (tris[k] == t) sentence(list[k], name: name, money: money),
        ].join(any ? ' or ' : ' and ');
    final after = [
      for (var k = 0; k < list.length; k++)
        if (tris[k] == _Tri.later) (list[k]['id'] as num).toInt(),
    ];
    final _Tri all;
    if (any) {
      all = tris.contains(_Tri.yes)
          ? _Tri.yes
          : (tris.contains(_Tri.later) ? _Tri.later : (tris.contains(_Tri.standby) ? _Tri.standby : _Tri.no));
    } else {
      all = tris.contains(_Tri.no)
          ? _Tri.no
          : (tris.contains(_Tri.standby) ? _Tri.standby : (tris.contains(_Tri.later) ? _Tri.later : _Tri.yes));
    }
    return switch (all) {
      _Tri.yes => met,
      _Tri.later => NeedResult(NeedState.after, after: after, why: 'Once ${words(_Tri.later)}'),
      _Tri.standby => NeedResult(NeedState.standby, why: 'Only if ${words(_Tri.standby)}'),
      _Tri.no => NeedResult(NeedState.off, why: 'Needs: ${any ? describe(needs, name: name, money: money) : words(_Tri.no)}'),
    };
  }

  /// Whether [needs] holds right now, with nothing still open. Used for "counts as done when".
  static bool holdsNow(Object? needs, NeedFacts f) {
    final list = checks(needs);
    if (list.isEmpty) return false;
    final tris = [for (final c in list) _check(c, f)];
    return (needs as Map)['any'] == true ? tris.contains(_Tri.yes) : tris.every((t) => t == _Tri.yes);
  }

  /// The opposite of [needs], for "otherwise do this instead".
  static Map<String, dynamic> opposite(Object? needs) => {
        'any': !(needs is Map && needs['any'] == true),
        'if': [
          for (final c in checks(needs))
            if (c['check'] == 'balance')
              {'check': 'balance', 'account': c['account'], if (c['atLeast'] != null) 'below': c['atLeast'] else 'atLeast': c['below']}
            else
              {...c, 'not': c['not'] != true},
        ],
      };
}
