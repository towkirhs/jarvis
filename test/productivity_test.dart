import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/productivity.dart';

void main() {
  final now = DateTime(2026, 11, 12, 10); // a Thursday
  int ms(DateTime d) => d.millisecondsSinceEpoch;

  group('Active recall (Leitner boxes)', () {
    test('a right answer moves the card up a box and further away; a miss sends it back to box 0', () {
      expect(Recall.review(0, true, now), (box: 1, due: ms(DateTime(2026, 11, 14))));
      expect(Recall.review(3, true, now), (box: 4, due: ms(DateTime(2026, 11, 28))));
      expect(Recall.review(4, false, now), (box: 0, due: ms(DateTime(2026, 11, 13))));
      expect(Recall.review(Recall.gaps.length - 1, true, now).box, Recall.gaps.length - 1);
    });

    test('a card is due on or before today', () {
      expect(Recall.isDue({'due': ms(DateTime(2026, 11, 12, 23))}, now), true);
      expect(Recall.isDue({'due': ms(DateTime(2026, 11, 13))}, now), false);
      expect(Recall.isDue({}, now), true);
    });
  });
}
