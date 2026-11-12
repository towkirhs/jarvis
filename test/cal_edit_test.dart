import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/cal_edit.dart';

void main() {
  final master = {
    'id': 7,
    'nid': 9,
    'kind': 'event',
    'title': 'Class',
    'when': 1,
    'repeat': 'weekly',
    'skip': ['2026-11-20'],
    'dur': 90,
    'location': 'Room 4',
    'color': 'teal',
    'status': 'open',
    'doneAt': 5,
  };

  test('a one-off copy keeps the details and drops the repeat and the bookkeeping', () {
    final f = CalEdit.oneOffFields(master);
    expect(f['dur'], 90);
    expect(f['location'], 'Room 4');
    expect(f['color'], 'teal');
    expect(f['repeat'], isNull);
    expect(f.containsKey('repeat'), isTrue);
    for (final k in ['id', 'nid', 'skip', 'status', 'doneAt', 'title', 'when']) {
      expect(f.containsKey(k), isFalse, reason: k);
    }
  });

  test('skipping a date adds it once, in date order', () {
    expect(CalEdit.skipped(master, '2026-11-13'), ['2026-11-13', '2026-11-20']);
    expect(CalEdit.skipped(master, '2026-11-20'), ['2026-11-20']);
    expect(CalEdit.skipped({'id': 1}, '2026-11-13'), ['2026-11-13']);
  });

  test('minutes: a duration, else an estimate, else an hour, never under 15', () {
    expect(CalEdit.minutes({'dur': 45}), 45);
    expect(CalEdit.minutes({'est': 30}), 30);
    expect(CalEdit.minutes({}), 60);
    expect(CalEdit.minutes({'dur': 5}), 15);
    expect(CalEdit.minutes({'dur': 99999}), 1440);
  });
}
