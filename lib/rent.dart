/// Rooms you rent out, kept as a running balance like a shop ledger: every month adds that month's rent plus
/// the bills from the month before (bills are paid with the next month's rent), every payment takes off what
/// it pays, and whatever is left carries into the next month. Pure Dart, tested on its own.
///
/// A room: {id, number, tenant, rent, advance, start: 'YYYY-MM', opening: earlier due when you started}.
/// A payment ('rentPays'): {id, room, amount, paidAt: ms, method: 'Cash' / 'bKash' / … or absent}.
/// A meeting with tenants is a calendar event ('items') with meeting: true, rooms: [room ids] (empty = all),
/// where: text, desc: notes.
/// A bill ('roomBills'): {id, room, month: 'YYYY-MM' it was used in, kind, amount}.
/// A house expense ('houseCosts'): {id, ts, amount, what, room: id or null}.
class Rent {
  static const monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const billKinds = {'electricity': 'Electricity', 'waste': 'Waste', 'wifi': 'Wi-Fi', 'other': 'Other bill'};

  static const payMethods = ['Cash', 'bKash', 'Nagad', 'Bank', 'Card'];

  /// A month's bill: 'paid' (nothing left), 'partial' (something paid, some left) or 'due' (nothing paid).
  static String status(MonthLine x) => x.left <= 0 ? 'paid' : (x.paid > 0 ? 'partial' : 'due');

  /// A meeting is over once it is marked done or its time has passed.
  static bool meetingDone(Map<String, dynamic> m, DateTime now) =>
      m['status'] == 'done' || (m['when'] as int) < now.millisecondsSinceEpoch;

  static String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  static DateTime parse(String month) {
    final p = month.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]));
  }

  static String shift(String month, int by) {
    final d = parse(month);
    return key(DateTime(d.year, d.month + by));
  }

  /// "2026-11" as "November 2026"; [short] gives "Nov".
  static String name(String month, {bool short = false}) {
    final d = parse(month);
    final n = monthNames[d.month - 1];
    return short ? n.substring(0, 3) : '$n ${d.year}';
  }

  /// Every month from [from] through [now]'s month, oldest first.
  static List<String> months(String from, DateTime now) {
    final out = <String>[];
    var d = parse(from);
    final end = DateTime(now.year, now.month);
    while (!d.isAfter(end)) {
      out.add(key(d));
      d = DateTime(d.year, d.month + 1);
    }
    return out;
  }

  /// Bills used in [month] (they are charged the month after).
  static List<Map<String, dynamic>> billsOf(int room, String month, List<Map<String, dynamic>> bills) =>
      bills.where((b) => b['room'] == room && b['month'] == month).toList();

  /// One month of one room, as on a statement.
  static MonthLine month(
    Map<String, dynamic> room,
    String month,
    List<Map<String, dynamic>> pays,
    List<Map<String, dynamic>> bills,
  ) {
    final id = room['id'] as int;
    final start = room['start'] as String;
    var carried = (room['opening'] as num?) ?? 0;
    for (final m in months(start, parse(month))) {
      final billed = billsOf(id, shift(m, -1), bills);
      final charge = (room['rent'] as num) + billed.fold<num>(0, (a, b) => a + (b['amount'] as num));
      final paid = pays.where((p) {
        if (p['room'] != id) return false;
        final k = key(DateTime.fromMillisecondsSinceEpoch(p['paidAt'] as int));
        // Anything paid before the first month counts in the first month.
        return k == m || (m == start && k.compareTo(start) < 0);
      }).toList()
        ..sort((a, b) => (a['paidAt'] as int).compareTo(b['paidAt'] as int));
      final paidSum = paid.fold<num>(0, (a, p) => a + (p['amount'] as num));
      final line = MonthLine(m, carried, room['rent'] as num, billed, paid, carried + charge - paidSum);
      if (m == month) return line;
      carried = line.left;
    }
    return MonthLine(month, carried, 0, const [], const [], carried);
  }

  /// What a room owes right now (negative means paid ahead).
  static num due(Map<String, dynamic> room, List<Map<String, dynamic>> pays, List<Map<String, dynamic>> bills, DateTime now) =>
      month(room, key(now), pays, bills).left;

  /// The oldest month that is still not fully paid, for "unpaid since October".
  static String? unpaidSince(Map<String, dynamic> room, List<Map<String, dynamic>> pays, List<Map<String, dynamic>> bills, DateTime now) {
    final left = due(room, pays, bills, now);
    if (left <= 0) return null;
    // Walk back from now, taking each month's charges, until they cover what is owed.
    num covered = 0;
    final all = months(room['start'] as String, now).reversed.toList();
    for (final m in all) {
      final line = month(room, m, pays, bills);
      covered += line.charge;
      if (covered >= left) return m;
    }
    return all.isEmpty ? null : all.last;
  }
}

/// A month on a room's statement.
class MonthLine {
  const MonthLine(this.month, this.carried, this.rent, this.bills, this.payments, this.left);

  final String month;

  /// Still owed from earlier months when this month began.
  final num carried;
  final num rent;

  /// Last month's bills, charged now.
  final List<Map<String, dynamic>> bills;
  final List<Map<String, dynamic>> payments;

  /// Owed at the end of the month (carried + rent + bills − paid).
  final num left;

  num get billTotal => bills.fold<num>(0, (a, b) => a + (b['amount'] as num));
  num get charge => rent + billTotal;
  num get paid => payments.fold<num>(0, (a, p) => a + (p['amount'] as num));
  num get toPay => carried + charge;
}
