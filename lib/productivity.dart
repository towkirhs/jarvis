/// Rules for learning, pure Dart and tested: active recall.

/// Active recall with Leitner boxes: a card you get right waits longer each time; a miss starts it over.
/// A card is `{deck, q, a, box, due}`.
class Recall {
  /// Days until the next review for a card in each box.
  static const gaps = [1, 2, 4, 8, 16, 32, 64];

  static ({int box, int due}) review(int box, bool gotIt, DateTime now) {
    final next = gotIt ? (box + 1).clamp(0, gaps.length - 1) : 0;
    final day = DateTime(now.year, now.month, now.day + gaps[next]);
    return (box: next, due: day.millisecondsSinceEpoch);
  }

  static bool isDue(Map<String, dynamic> card, DateTime now) =>
      ((card['due'] as int?) ?? 0) < DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
}
