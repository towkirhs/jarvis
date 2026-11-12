import 'dart:convert';

/// Merging two copies of Jarvis's data (this device and the synced copy). Pure Dart, tested on its own.
///
/// Every record carries `_t`, when it last changed (set by [Stamps] on save). Deleted records leave a mark in
/// `_gone` ('items:42' → when). When both devices changed, each record keeps its newer version, and a record
/// deleted on either device stays deleted unless it was edited after the delete.
class SyncMerge {
  /// Ids from each device live in their own range, so two devices never make the same id.
  static const rangeSize = 10000000;

  /// Deletion marks older than this are dropped; every device has synced by then.
  static const keepGone = 90 * 86400000;

  /// A list of records with ids: any top-level list whose entries are maps with an 'id'.
  static bool isCollection(Object? v) => v is List && v.isNotEmpty && v.every((r) => r is Map && r['id'] != null);

  /// Combines [local] and [remote]. If nothing changed here, the remote copy is taken as it is.
  /// Otherwise records are joined by id (newer `_t` wins, this device on a tie), deletions are applied,
  /// and maps (summaries, settings) are joined key by key with this device winning.
  /// 'next' stays this device's own counter, kept inside its range ([slot]).
  static Map<String, dynamic> merge(
    Map<String, dynamic> local,
    Map<String, dynamic> remote, {
    required bool localChanged,
    required int slot,
    int? now,
  }) {
    final ownNext = (local['next'] as int?) ?? 100;
    final floor = slot * rangeSize;
    final next = ownNext >= floor && ownNext < floor + rangeSize ? ownNext : floor + 1;
    if (!localChanged) {
      return <String, dynamic>{...local, ...remote, 'next': next};
    }
    final out = <String, dynamic>{...remote, ...local};
    final t = now ?? DateTime.now().millisecondsSinceEpoch;
    final gone = <String, dynamic>{};
    for (final g in [remote['_gone'], local['_gone']]) {
      for (final e in ((g as Map?) ?? const {}).entries) {
        final at = e.value as int;
        if (t - at > keepGone) continue;
        if (at > ((gone[e.key] as int?) ?? -1)) gone[e.key] = at;
      }
    }
    int stamp(Map r) => (r['_t'] as int?) ?? 0;
    Object keyOf(Map r) => r['id'] ?? Object.hashAll([for (final e in r.entries) '${e.key}=${e.value}']);
    final cols = {
      for (final m in [local, remote])
        for (final e in m.entries)
          if (!e.key.startsWith('_') && isCollection(e.value)) e.key,
    };
    for (final c in cols) {
      final byId = <Object, Map<String, dynamic>>{};
      for (final r in (remote[c] as List?) ?? const []) {
        byId[keyOf(r as Map)] = Map<String, dynamic>.from(r);
      }
      for (final r in (local[c] as List?) ?? const []) {
        final mine = Map<String, dynamic>.from(r as Map);
        final theirs = byId[keyOf(mine)];
        if (theirs == null || stamp(mine) >= stamp(theirs)) byId[keyOf(mine)] = mine;
      }
      out[c] = [
        for (final r in byId.values)
          if (r['id'] == null || ((gone['$c:${r['id']}'] as int?) ?? -1) < stamp(r)) r,
      ];
    }
    for (final m in ['summaries', 'boosts', 'settings']) {
      out[m] = <String, dynamic>{
        ...((remote[m] as Map?) ?? const {}).cast<String, dynamic>(),
        ...((local[m] as Map?) ?? const {}).cast<String, dynamic>(),
      };
    }
    out['_gone'] = gone;
    out['next'] = next;
    return out;
  }
}

/// Marks what changed between saves: a changed or new record gets `_t`, a missing one a mark in `_gone`.
class Stamps {
  static int _hash(Map r) => jsonEncode({for (final e in r.entries) if (e.key != '_t') e.key: e.value}).hashCode;

  /// Per collection, each record's id and content hash.
  static Map<String, Map<Object, int>> snapshot(Map<String, dynamic> state) => {
        for (final e in state.entries)
          if (!e.key.startsWith('_') && SyncMerge.isCollection(e.value))
            e.key: {for (final r in e.value as List) (r as Map)['id'] as Object: _hash(r)},
      };

  /// Stamps [state] against [before] at [now] and returns the new snapshot.
  static Map<String, Map<Object, int>> stamp(Map<String, dynamic> state, Map<String, Map<Object, int>> before, int now) {
    final after = <String, Map<Object, int>>{};
    for (final e in state.entries.toList()) { // the loop may add '_gone'
      if (e.key.startsWith('_') || e.value is! List) continue;
      final was = before[e.key] ?? const {};
      final seen = <Object, int>{};
      for (final r in e.value as List) {
        if (r is! Map || r['id'] == null) continue;
        final h = _hash(r);
        if (was[r['id']] != h) r['_t'] = now;
        seen[r['id'] as Object] = h;
      }
      for (final id in was.keys) {
        if (!seen.containsKey(id)) ((state['_gone'] ??= <String, dynamic>{}) as Map)['${e.key}:$id'] = now;
      }
      after[e.key] = seen;
    }
    return after;
  }
}
