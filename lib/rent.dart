/// Rooms you rent out: what each month costs the tenant (rent plus that month's electricity bill), what they
/// paid for it, and what is still due. Pure Dart, tested on its own.
///
/// A room: {id, number, tenant, rent, advance, start: 'YYYY-MM'}.
/// A payment ('rentPays'): {id, room, month: 'YYYY-MM' it pays for, amount, paidAt: ms}.
/// A bill ('roomBills'): {id, room, month: 'YYYY-MM', amount}.
class Rent {
  static const monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  static DateTime _parse(String month) {
    final p = month.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]));
  }

  /// "2026-11" as "November 2026".
  static String name(String month) {
    final d = _parse(month);
    return '${monthNames[d.month - 1]} ${d.year}';
  }

  /// Every month from [from] through [now]'s month, oldest first.
  static List<String> months(String from, DateTime now) {
    final out = <String>[];
    var d = _parse(from);
    final end = DateTime(now.year, now.month);
    while (!d.isAfter(end)) {
      out.add(key(d));
      d = DateTime(d.year, d.month + 1);
    }
    return out;
  }

  static num _sum(List<Map<String, dynamic>> recs, int room, String month) => recs
      .where((r) => r['room'] == room && r['month'] == month)
      .fold<num>(0, (a, r) => a + (r['amount'] as num));

  /// One month for one room: what was owed (rent + bill), paid, and is still due (negative = paid extra).
  static ({num rent, num bill, num paid, num due}) month(
    Map<String, dynamic> room,
    String month,
    List<Map<String, dynamic>> pays,
    List<Map<String, dynamic>> bills,
  ) {
    final id = room['id'] as int;
    final rent = room['rent'] as num;
    final bill = _sum(bills, id, month);
    final paid = _sum(pays, id, month);
    return (rent: rent, bill: bill, paid: paid, due: rent + bill - paid);
  }

  /// Everything still owed for a room, from its first month to now. Extra paid in one month counts
  /// towards another, so the total is what the tenant really owes.
  static num totalDue(
    Map<String, dynamic> room,
    List<Map<String, dynamic>> pays,
    List<Map<String, dynamic>> bills,
    DateTime now,
  ) =>
      months(room['start'] as String, now).fold<num>(0, (a, m) => a + month(room, m, pays, bills).due);
}
