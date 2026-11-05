import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/money_sms.dart';

final now = DateTime(2026, 11, 6, 9);

MoneyEvent? parse(String text, {String from = 'bKash'}) => MoneySms.parse(text, from: from, now: now);

void main() {
  test('bKash money received (real format)', () {
    final e = parse('You have received Tk 800.00 from 01999999999.Ref XYZ. Fee Tk 0.00. Balance Tk 1,250.50. TrxID BKX7Y8Z9Q1 at 15/07/2021 11:00')!;
    expect([e.type, e.amount, e.account, e.trxId, e.note], ['income', 800, 'bKash', 'BKX7Y8Z9Q1', 'From 01999999999']);
    expect(e.ts, DateTime(2021, 7, 15, 11, 0));
  });

  test('bKash cash in is a transfer from cash', () {
    final e = parse('Cash In Tk 3,260.00 from 01999999999 successful. Fee Tk 0.00. Balance Tk 0.00. TrxID ABC1234567 at 14/07/2021 20:19.')!;
    expect([e.type, e.amount, e.account, e.toAccount], ['transfer', 3260, 'Cash', 'bKash']);
  });

  test('bKash cash out includes the fee', () {
    final e = parse('Cash Out Tk 1,000.00 to 01888888888 successful. Fee Tk 18.50. Balance Tk 500.00. TrxID QWE1234567 at 06/11/2026 08:30')!;
    expect([e.type, e.amount, e.account, e.toAccount], ['transfer', 1018.5, 'bKash', 'Cash']);
  });

  test('bKash send money is an expense to label', () {
    final e = parse('Send Money Tk 500.00 to 01777777777 successful. Ref lunch. Fee Tk 0.00. Balance Tk 750.50. TrxID ZXC9876543 at 06/11/2026 13:10')!;
    expect([e.type, e.amount, e.category, e.note], ['expense', 500, 'Other', 'To 01777777777']);
  });

  test('bKash merchant payment', () {
    final e = parse('Payment Tk 250.00 to Shwapno (01700000000) successful. Fee Tk 0.00. Balance Tk 500.50. TrxID MNB1234567 at 06/11/2026 18:00')!;
    expect([e.type, e.amount, e.category, e.note], ['expense', 250, 'Shopping', 'To Shwapno']);
  });

  test('Nagad money received (real format)', () {
    final e = parse('Money Received. Amount: Tk 2,500.00. Sender: 01735254295. TxnID: 72J9KA21. Ref: Order #46. 16/10/2026 11:30', from: 'NAGAD')!;
    expect([e.type, e.amount, e.account, e.trxId], ['income', 2500, 'Nagad', '72J9KA21']);
    expect(e.ts, DateTime(2026, 10, 16, 11, 30));
  });

  test('bank debit', () {
    final e = parse('Your A/C XXXX1234 has been debited by BDT 1,200.00 on 05-11-2026 for POS purchase at DARAZ. Avl Bal BDT 20,000.00', from: 'DBBL-BANK')!;
    expect([e.type, e.amount, e.account], ['expense', 1200, 'Bank']);
  });

  test('bank credit', () {
    final e = parse('Your A/C XXXX1234 is credited with BDT 15,000.00 (Salary). Avl Bal BDT 35,000.00', from: 'CITYBANK')!;
    expect([e.type, e.amount], ['income', 15000]);
  });

  group('ignored', () {
    for (final text in [
      'Your bKash verification code is 123456. Do not share it.',
      'Get 10% cashback on Payment of Tk 500 or more at Daraz! Offer valid till 30 Nov.',
      'Dear customer, your bill of Tk 450 is due on 10 Nov.',
    ]) {
      test(text, () => expect(parse(text), isNull));
    }
  });
}
