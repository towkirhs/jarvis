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
