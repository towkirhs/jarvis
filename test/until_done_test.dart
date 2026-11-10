import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/store.dart';

void main() {
  int ms(int d, int h, [int m = 0]) => DateTime(2026, 11, d, h, m).millisecondsSinceEpoch;

  test('a reminder still ahead keeps its own time', () {
    expect(Store.nextDaily(ms(12, 20), DateTime(2026, 11, 10, 9)), ms(12, 20));
  });

  test('a missed one comes back at the same clock time, today or tomorrow', () {
    expect(Store.nextDaily(ms(8, 20), DateTime(2026, 11, 10, 9)), ms(10, 20));
    expect(Store.nextDaily(ms(8, 20), DateTime(2026, 11, 10, 21)), ms(11, 20));
    expect(Store.nextDaily(ms(10, 20), DateTime(2026, 11, 10, 20)), ms(11, 20));
  });
}
