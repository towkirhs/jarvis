import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/clash.dart';

void main() {
  test('a reminder is the chosen number of days before, at the chosen time', () {
    final day = DateTime(2026, 12, 20);
    expect(CountdownAlert.at(day, '09:00', 0), DateTime(2026, 12, 20, 9));
    expect(CountdownAlert.at(day, '18:30', 7), DateTime(2026, 12, 13, 18, 30));
    expect(CountdownAlert.at(DateTime(2026, 12, 2), '08:00', 3), DateTime(2026, 11, 29, 8));
  });

  test('the on-the-day reminder keeps the countdown id; others get their own', () {
    expect(CountdownAlert.id(41, 0), 41);
    final ids = {for (final d in CountdownAlert.days) CountdownAlert.id(41, d)};
    expect(ids.length, CountdownAlert.days.length);
    expect(CountdownAlert.id(42, 1), isNot(CountdownAlert.id(41, 7)));
    expect(CountdownAlert.id(9000000, 30), lessThan(2147483647));
  });

  test('the notification says how far away it is', () {
    expect(CountdownAlert.label('Exam', 0), 'Today: Exam');
    expect(CountdownAlert.label('Exam', 1), 'Tomorrow: Exam');
    expect(CountdownAlert.label('Exam', 7), 'In 7 days: Exam');
  });
}
