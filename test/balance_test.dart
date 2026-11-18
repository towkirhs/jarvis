import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/brain.dart';
import 'package:jarcis/local_parser.dart';
import 'package:jarcis/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _accounts = ['Cash', 'Bank', 'bKash'];

Future<Store> _store({num cash = 1907}) async {
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (call) async => null);
  final s = Store();
  await s.load();
  s.list('accounts').firstWhere((a) => a['name'] == 'Cash')['initial'] = cash;
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('balance sentences are read on the phone; other money notes are not', () {
    final b = LocalParser.balance('I have 1877 taka in cash else used for transport update the cash', _accounts)!;
    expect([b['account'], b['leaves'], b['category']], ['Cash', 1877, 'Transport']);
    expect(LocalParser.balance('cash is 830', _accounts)!['category'], 'Balance correction');
    expect(LocalParser.balance('make bkash 500', _accounts)!['account'], 'bKash');
    expect(LocalParser.balance('bank balance 5,200', _accounts)!['leaves'], 5200);
    expect(LocalParser.balance('set cash to 830', _accounts)!['leaves'], 830);
    expect(LocalParser.balance('spent 200 on food from cash', _accounts), isNull);
    expect(LocalParser.balance('I have 3 tuitions tomorrow', _accounts), isNull);
    expect(LocalParser.balance('cashback is 50', _accounts), isNull);
  });

  test('"I have 1877 in cash, the rest on transport" records the ৳30 and leaves Cash at 1877', () async {
    final s = await _store();
    await Brain.capture(s, 'I have 1877 taka in cash else used for transport update the cash');
    final tx = s.list('tx').single;
    expect([tx['type'], tx['amount'], tx['cat'], tx['account']], ['expense', 30, 'Transport', 'Cash']);
    expect(s.balance(s.list('accounts').firstWhere((a) => a['name'] == 'Cash')), 1877);
    expect(s.list('captures').single['msg'], contains('Cash now'));
  });

  test('more cash than recorded comes in as a balance correction', () async {
    final s = await _store();
    await Brain.capture(s, 'cash is 2000');
    final tx = s.list('tx').single;
    expect([tx['type'], tx['amount'], tx['cat']], ['income', 93, 'Balance correction']);
    expect(s.balance(s.list('accounts').firstWhere((a) => a['name'] == 'Cash')), 2000);
  });

  test('a reply that claims an action is caught; questions and answers are not', () {
    expect(Brain.claimsAction("Got it, I've updated your cash balance to 1877 Taka."), isTrue);
    expect(Brain.claimsAction('Sure, I set alarms for 5:00 am and 6:00 am today.'), isTrue);
    expect(Brain.claimsAction('Your expense has been recorded.'), isTrue);
    expect(Brain.claimsAction('What would you like to call it?'), isFalse);
    expect(Brain.claimsAction('Your next alarm is at 6 am.'), isFalse);
    expect(Brain.claimsAction("I've noted that. Enjoy the movie!"), isFalse);
  });

  test('"create a money manager account named Oishi" and "delete food 20" are read on the phone', () {
    expect(LocalParser.moneyCommand('Create a money manager account named Oishi'), {'type': 'account', 'title': 'Oishi', 'confidence': 1.0});
    expect(LocalParser.moneyCommand('add account savings')!['title'], 'Savings');
    final d = LocalParser.moneyCommand('Delete food 20')!;
    expect([d['type'], d['amount'], d['title']], ['money_delete', 20, 'food']);
    expect(LocalParser.moneyCommand('remove the 20 taka food entry')!['title'], 'food');
    expect(LocalParser.moneyCommand('delete 150')!['title'], '');
    expect(LocalParser.moneyCommand('delete the gym task'), isNull);
    expect(LocalParser.moneyCommand('spent 20 on food'), isNull);
  });

  test('in the chat: a new account, and deleting the latest matching entry (with Undo)', () async {
    final s = await _store();
    await Brain.capture(s, 'Create a money manager account named Oishi');
    expect(s.list('accounts').where((a) => a['name'] == 'Oishi'), hasLength(1));
    await Brain.capture(s, 'create account oishi');
    expect(s.list('captures').last['msg'], 'You already have an account named Oishi');

    s.addTx(type: 'expense', amount: 20, category: 'Food', account: 'Cash', ts: DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch);
    s.addTx(type: 'expense', amount: 20, category: 'Transport', account: 'Cash');
    await Brain.capture(s, 'Delete food 20');
    expect(s.list('tx').single['cat'], 'Transport');
    expect(s.list('captures').last['msg'], startsWith('Deleted: '));
    await s.undo(s.list('captures').last['actionId'] as int);
    expect(s.list('tx'), hasLength(2));

    await Brain.capture(s, 'delete food 999');
    expect(s.list('captures').last['msg'], contains('nothing was deleted'));
  });
}
