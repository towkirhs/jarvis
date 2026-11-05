/// Reads transaction messages from bKash, Nagad, Rocket and banks (SMS or app notifications).
/// Pure Dart so it can be tested on its own.
class MoneyEvent {
  MoneyEvent({
    required this.type,
    required this.amount,
    required this.account,
    this.toAccount,
    required this.category,
    this.note,
    this.trxId,
    required this.ts,
  });

  /// 'income', 'expense' or 'transfer'.
  final String type;
  final num amount;
  final String account;
  final String? toAccount;
  final String category;
  final String? note;
  final String? trxId;
  final DateTime ts;
}

class MoneySms {
  static final _amount = RegExp(r'(?:Tk|BDT|৳)\.?\s*([\d,]+(?:\.\d+)?)', caseSensitive: false);
  static final _trx = RegExp(r'\b(?:TrxID|TxnID|Trx\s?ID|Txn\s?ID|Transaction\s?ID|Ref\.?\s?No)[:.\s]*([A-Z0-9]{6,})', caseSensitive: false);
  static final _date = RegExp(r'(\d{1,2})[/-](\d{1,2})[/-](\d{4})\s+(\d{1,2}):(\d{2})');
  static final _marker = RegExp(
    r'\b(TrxID|TxnID|Trx\s?ID|Txn\s?ID|successful|debited|credited|received|Cash\s?In|Cash\s?Out|Send\s?Money|Payment|withdrawn|deposited|purchase)\b',
    caseSensitive: false,
  );
  static final _junk = RegExp(r'\b(OTP|verification code|PIN|offer|cashback|discount|win|chance|%)\b', caseSensitive: false);

  /// Which account a message is about, from the sender or the text.
  static String accountOf(String from, String text) {
    final s = '$from $text'.toLowerCase();
    if (s.contains('bkash')) return 'bKash';
    if (s.contains('nagad')) return 'Nagad';
    if (s.contains('rocket') || s.contains('16216')) return 'Rocket';
    if (s.contains('upay')) return 'Upay';
    return 'Bank';
  }

  /// The amount that is not a fee or a balance.
  static num? _mainAmount(String text) {
    for (final m in _amount.allMatches(text)) {
      final before = text.substring(m.start > 12 ? m.start - 12 : 0, m.start).toLowerCase();
      if (before.contains('fee') || before.contains('balance') || before.contains('bal') || before.contains('charge')) continue;
      return num.parse(m.group(1)!.replaceAll(',', ''));
    }
    return null;
  }

  static num _fee(String text) {
    final m = RegExp(r'(?:fee|charge)\s*(?:Tk|BDT|৳)?\.?\s*([\d,]+(?:\.\d+)?)', caseSensitive: false).firstMatch(text);
    return m == null ? 0 : num.parse(m.group(1)!.replaceAll(',', ''));
  }

  /// Returns null for messages that are not a completed transaction (OTPs, offers, reminders).
  static MoneyEvent? parse(String text, {String from = '', required DateTime now}) {
    final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (!_marker.hasMatch(t) || _junk.hasMatch(t)) return null;
    final amount = _mainAmount(t);
    if (amount == null || amount <= 0) return null;
    final lower = t.toLowerCase();
    final account = accountOf(from, t);
    final fee = _fee(t);

    final d = _date.firstMatch(t);
    final ts = d == null
        ? now
        : DateTime(int.parse(d.group(3)!), int.parse(d.group(2)!), int.parse(d.group(1)!), int.parse(d.group(4)!), int.parse(d.group(5)!));
    final trx = _trx.firstMatch(t)?.group(1);
    String? party(String word) =>
        RegExp('\\b$word\\s+([A-Za-z0-9][A-Za-z0-9 .&\'-]{1,40}?)(?=\\s*(?:\\(|\\.|,| successful| Ref|\$))').firstMatch(t)?.group(1)?.trim();

    // Moving money between your own wallet and cash.
    if (RegExp(r'\bcash\s?out\b').hasMatch(lower)) {
      return MoneyEvent(type: 'transfer', amount: amount + fee, account: account, toAccount: 'Cash', category: 'Transfer', note: 'Cash out', trxId: trx, ts: ts);
    }
    if (RegExp(r'\bcash\s?in\b').hasMatch(lower)) {
      return MoneyEvent(type: 'transfer', amount: amount, account: 'Cash', toAccount: account, category: 'Transfer', note: 'Cash in', trxId: trx, ts: ts);
    }

    final income = RegExp(r'\b(received|credited|deposited|deposit|refund|money received)\b').hasMatch(lower) &&
        !RegExp(r'\b(debited|payment to|send money)\b').hasMatch(lower);
    final expense = RegExp(r'\b(send money|payment|paid|debited|purchase|withdrawn|bill|recharge|sent)\b').hasMatch(lower);
    if (!income && !expense) return null;

    if (income) {
      final who = party('from');
      return MoneyEvent(type: 'income', amount: amount, account: account, category: 'Other', note: who == null ? null : 'From $who', trxId: trx, ts: ts);
    }
    final category = lower.contains('recharge') || lower.contains('bill')
        ? 'Bills'
        : (lower.contains('payment') || lower.contains('purchase') ? 'Shopping' : 'Other');
    final who = party('to') ?? party('at');
    return MoneyEvent(
      type: 'expense',
      amount: amount + fee,
      account: account,
      category: category,
      note: who == null ? null : (lower.contains('recharge') ? 'Recharge $who' : 'To $who'),
      trxId: trx,
      ts: ts,
    );
  }
}
