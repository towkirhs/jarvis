import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/sync.dart';
import 'package:jarcis/sync_merge.dart';

Map<String, dynamic> state(List<Map<String, dynamic>> items, {int next = 100, Map<String, dynamic>? settings}) => {
      'items': items,
      'captures': <dynamic>[],
      'settings': settings ?? <String, dynamic>{},
      'next': next,
    };

void main() {
  codeTests();
  stampTests();
  test('nothing changed here: the synced copy is taken as it is, so deletions stick', () {
    final local = state([
      {'id': 1, 'title': 'Old'},
      {'id': 2, 'title': 'Deleted elsewhere'},
    ]);
    final remote = state([
      {'id': 1, 'title': 'Renamed elsewhere'},
    ]);
    final m = SyncMerge.merge(local, remote, localChanged: false, slot: 3);
    expect(m['items'], [
      {'id': 1, 'title': 'Renamed elsewhere'},
    ]);
    expect(m['next'], 30000001);
  });

  test('both changed: records are joined and this device wins on the same id', () {
    final local = state([
      {'id': 1, 'title': 'Mine'},
      {'id': 30000005, 'title': 'New here'},
    ], next: 30000006, settings: {'theme': 'dark'});
    final remote = state([
      {'id': 1, 'title': 'Theirs'},
      {'id': 70000002, 'title': 'New there'},
    ], next: 70000003, settings: {'theme': 'light', 'currency': '৳'});
    final m = SyncMerge.merge(local, remote, localChanged: true, slot: 3);
    expect((m['items'] as List).map((r) => r['title']).toSet(), {'Mine', 'New here', 'New there'});
    expect(m['settings'], {'theme': 'dark', 'currency': '৳'});
    expect(m['next'], 30000006);
  });

  test('encryption round trip, and the wrong passphrase fails', () async {
    final salt = List<int>.generate(16, (i) => i);
    final key = await Sync.deriveKey('correct horse', salt);
    final data = state([
      {'id': 1, 'title': 'Pay rent ৳ 12,000'},
    ]);
    final envelope = await Sync.encrypt(data, key, salt);
    expect(envelope.contains('Pay rent'), isFalse);
    expect(await Sync.decrypt(envelope, key), data);
    final wrong = await Sync.deriveKey('wrong horse', salt);
    expect(() => Sync.decrypt(envelope, wrong), throwsA(anything));
  });
}

void stampTests() {
  group('record times and deletions', () {
    test('saving stamps only the records that changed, and remembers deletions', () {
      final s = <String, dynamic>{
        'items': [
          {'id': 1, 'title': 'A'},
          {'id': 2, 'title': 'B'},
          {'id': 3, 'title': 'C'},
        ],
        'settings': <String, dynamic>{},
      };
      final before = Stamps.snapshot(s);
      (s['items'] as List)[1]['title'] = 'B2';
      (s['items'] as List).removeAt(2);
      (s['items'] as List).add({'id': 4, 'title': 'D'});
      Stamps.stamp(s, before, 500);
      expect([for (final r in s['items'] as List) r['_t']], [null, 500, 500]);
      expect(s['_gone'], {'items:3': 500});
    });

    test('a later save with no change stamps nothing', () {
      final s = <String, dynamic>{
        'items': [
          {'id': 1, 'title': 'A', '_t': 10},
        ],
      };
      final snap = Stamps.snapshot(s);
      Stamps.stamp(s, snap, 900);
      expect((s['items'] as List).first['_t'], 10);
      expect(s['_gone'], isNull);
    });
  });

  group('merging when both devices changed', () {
    Map<String, dynamic> st(List<Map<String, dynamic>> items, [Map<String, dynamic>? gone]) =>
        {'items': items, 'settings': <String, dynamic>{}, 'next': 30000001, if (gone != null) '_gone': gone};

    test('the newer edit wins, whichever device it was on', () {
      final local = st([
        {'id': 1, 'title': 'Phone old', '_t': 100},
        {'id': 2, 'title': 'Phone new', '_t': 300},
      ]);
      final remote = st([
        {'id': 1, 'title': 'Web new', '_t': 200},
        {'id': 2, 'title': 'Web old', '_t': 250},
      ]);
      final m = SyncMerge.merge(local, remote, localChanged: true, slot: 3, now: 1000);
      expect([for (final r in m['items'] as List) r['title']], ['Web new', 'Phone new']);
    });

    test('a deletion on either device sticks, unless the record was edited after it', () {
      final local = st([
        {'id': 1, 'title': 'Deleted on web', '_t': 100},
        {'id': 3, 'title': 'Edited here after the delete', '_t': 400},
      ], {'items:2': 150});
      final remote = st([
        {'id': 2, 'title': 'Deleted on phone', '_t': 100},
        {'id': 3, 'title': 'old', '_t': 50},
      ], {'items:1': 200, 'items:3': 300});
      final m = SyncMerge.merge(local, remote, localChanged: true, slot: 3, now: 1000);
      expect([for (final r in m['items'] as List) r['title']], ['Edited here after the delete']);
      expect(m['_gone'], {'items:1': 200, 'items:2': 150, 'items:3': 300});
    });

    test('new collections are merged without being listed, and old deletion marks are dropped after 90 days', () {
      final day = 86400000;
      final local = {
        'newThing': [
          {'id': 1, 'v': 'a', '_t': 5},
        ],
        '_gone': {'items:9': 1},
        'next': 30000001,
      };
      final remote = {
        'newThing': [
          {'id': 2, 'v': 'b', '_t': 5},
        ],
        'next': 1,
      };
      final m = SyncMerge.merge(local, remote, localChanged: true, slot: 3, now: 100 * day);
      expect((m['newThing'] as List).length, 2);
      expect(m['_gone'], isEmpty);
    });
  });
}

void codeTests() {
  test('a setup code carries the token, gist and key, and nothing reads a wrong code', () {
    final code = Sync.makeCode(token: 'ghp_x', gist: 'abc', key: 'S0VZ', salt: 'U0FMVA==');
    expect(code.startsWith('JARVIS-SYNC1.'), true);
    expect(Sync.readCode('  $code\n'), (token: 'ghp_x', gist: 'abc', key: 'S0VZ', salt: 'U0FMVA=='));
    expect(Sync.readCode('hello'), isNull);
    expect(Sync.readCode('JARVIS-SYNC1.%%%'), isNull);
  });
}
