import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/month_view.dart';

void main() {
  test('November 2026 is six Monday-first weeks', () {
    final w = MonthView.weeks(DateTime(2026, 11, 9));
    expect(w.length, 6);
    expect(w.first.first, DateTime(2026, 10, 26));
    expect(w.last.last, DateTime(2026, 12, 6));
    expect(w.every((r) => r.length == 7), isTrue);
    expect(w.first.first.weekday, DateTime.monday);
  });
  test('February 2027 fits four weeks', () {
    final w = MonthView.weeks(DateTime(2027, 2, 1));
    expect(w.length, 4);
    expect(w.first.first, DateTime(2027, 2, 1));
    expect(w.last.last, DateTime(2027, 2, 28));
  });
  test('days run one after another', () {
    final all = [for (final w in MonthView.weeks(DateTime(2026, 3, 1))) ...w];
    for (var i = 1; i < all.length; i++) {
      expect(all[i], DateTime(all[i - 1].year, all[i - 1].month, all[i - 1].day + 1));
    }
  });
}
