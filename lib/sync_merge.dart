/// Merging two copies of Jarvis's data (this device and the synced copy). Pure Dart, tested on its own.
class SyncMerge {
  /// Collections of records with an 'id'.
  static const collections = [
    'captures', 'items', 'habits', 'promises', 'decisions', 'inbox', 'actions', 'countdowns', 'focus', 'tx',
    'entries', 'accounts',
  ];

  /// Ids from each device live in their own range, so two devices never make the same id.
  static const rangeSize = 10000000;

  /// Combines [local] and [remote]. If nothing changed here, the remote copy is taken as it is (so deletions on
  /// other devices stick). Otherwise records are joined by id, and this device's copy wins when both have one. Maps (summaries, settings) are joined key by key the
  /// same way. 'next' stays this device's own counter, kept inside its range ([slot]).
  static Map<String, dynamic> merge(
    Map<String, dynamic> local,
    Map<String, dynamic> remote, {
    required bool localChanged,
    required int slot,
  }) {
    final out = <String, dynamic>{...remote, ...local};
    final ownNext = (local['next'] as int?) ?? 100;
    final floor = slot * rangeSize;
    final next = ownNext >= floor && ownNext < floor + rangeSize ? ownNext : floor + 1;
    if (!localChanged) {
      return <String, dynamic>{...local, ...remote, 'next': next};
    }
    final winner = local;
    final loser = remote;
    Object? keyOf(Map r) => r['id'] ?? Object.hashAll([for (final e in r.entries) '${e.key}=${e.value}']);
    for (final c in collections) {
      final byId = <Object?, Map<String, dynamic>>{};
      for (final r in (loser[c] as List?) ?? const []) {
        byId[keyOf(r as Map)] = Map<String, dynamic>.from(r);
      }
      for (final r in (winner[c] as List?) ?? const []) {
        byId[keyOf(r as Map)] = Map<String, dynamic>.from(r);
      }
      out[c] = byId.values.toList();
    }
    for (final m in ['summaries', 'boosts', 'settings']) {
      out[m] = <String, dynamic>{
        ...((loser[m] as Map?) ?? const {}).cast<String, dynamic>(),
        ...((winner[m] as Map?) ?? const {}).cast<String, dynamic>(),
      };
    }
    out['next'] = next;
    return out;
  }
}
