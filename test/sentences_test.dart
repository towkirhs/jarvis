import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/brain.dart';
import 'package:jarcis/bugs.dart';
import 'package:jarcis/day_log.dart';
import 'package:jarcis/destination.dart';
import 'package:jarcis/local_parser.dart';
import 'package:jarcis/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real sentences you typed, and what the phone must do with them, with no AI.
/// Every caught bug about a misread sentence that the phone should handle gets a line here,
/// so the same mistake can never come back.
const _accounts = ['Cash', 'Bank', 'bKash'];

/// Sentence → [account, cash left, category] for a balance.
const _balances = {
  'I have 1877 taka in cash else used for transport update the cash': ['Cash', 1877, 'Transport'],
  'I have 1687 rest is expenses transport': ['Cash', 1687, 'Transport'],
  'Make 1187 cash  transport': ['Cash', 1187, 'Transport'],
  'cash: 1687 transport': ['Cash', 1687, 'Transport'],
  'cash is 830': ['Cash', 830, 'Balance correction'],
  'make bkash 500': ['bKash', 500, 'Balance correction'],
};

/// Sentences that must NOT be read as money by the phone.
const _notMoney = [
  'I have 3 tuitions tomorrow',
  'make 3 copies of the cash memo',
  'cashback is 50',
  'want to go to Shishu Hospital',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final e in _balances.entries) {
    test('balance: "${e.key}"', () {
      final b = LocalParser.commands(e.key, _accounts)?.single ?? LocalParser.balance(e.key, _accounts);
      expect(b, isNotNull);
      expect([b!['account'], b['leaves'], b['category']], e.value);
    });
  }

  for (final t in _notMoney) {
    test('not money: "$t"', () {
      expect(LocalParser.balance(t, _accounts), isNull);
      expect(LocalParser.commands(t, _accounts), isNull);
    });
  }

  test('"now" notes, and plans that are not', () {
    expect(NowLog.parse('started gym')?.verb, 'start');
    expect(NowLog.parse('back home')?.verb, 'back');
    expect(NowLog.parse('start gym at 6'), isNull);
  });

  test('"bug: …" catches the message before it, with no AI', () async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (_) async => null);
    final s = Store();
    await s.load();
    expect(Destination.of('bug: it should set cash')?.type, 'bug');
    await Brain.capture(s, 'cash is 830');
    await Brain.capture(s, 'bug: it should also say how much went to transport');
    final b = s.list('bugs').single;
    expect([b['note'], b['said'], b['screen']], ['it should also say how much went to transport', 'cash is 830', 'Chat']);
    expect(s.list('captures').last['via'], 'phone');
    final text = Bugs.report(s.list('bugs'));
    expect(text, contains('I said: cash is 830'));
    expect(text, contains('Jarvis did: '));
  });
}
