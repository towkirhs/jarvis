import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/brain.dart';
import 'package:jarcis/haptics.dart';
import 'package:jarcis/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Store> _store() async {
  Haptics.on = false;
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (_) async => null);
  final s = Store();
  await s.load();
  return s;
}

void _income(Store s, num v) => s.addTx(type: 'income', amount: v, category: 'Tuition', account: 'Cash');
List<Map> _tasks(Store s, String title) => s.list('items').where((i) => i['title'] == title).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Duaris cream: waits until income lands in Cash with 500 there, acts once, and can be undone', () async {
    final s = await _store();
    final undo = <Map<String, dynamic>>[];
    final msg = await Brain.applyParsed(s, {
      'type': 'rule',
      'title': 'Buy Duaris cream',
      'rule': {
        'when': {'on': 'money', 'moneyType': 'income', 'account': 'Cash'},
        'if': [{'check': 'balance', 'account': 'Cash', 'atLeast': 500}],
        'then': [{'do': 'task', 'title': 'Buy Duaris cream', 'day': 0}],
        'once': true,
      },
    }, 1, const [], undo);
    expect(msg, startsWith('Rule: When income is added to Cash'));
    s.save();

    s.addTx(type: 'expense', amount: 100, category: 'Food', account: 'Cash');
    _income(s, 300); // Cash is 200: not enough yet
    expect(_tasks(s, 'Buy Duaris cream'), isEmpty);

    _income(s, 400); // Cash is 600
    expect(_tasks(s, 'Buy Duaris cream').length, 1);
    final rule = s.list('rules').firstWhere((r) => r['name'] == 'Buy Duaris cream');
    expect(rule['on'], false);
    expect(s.ruleNotice.value?.text, contains('Buy Duaris cream'));

    _income(s, 400); // once: no second task
    expect(_tasks(s, 'Buy Duaris cream').length, 1);

    await s.undo(s.ruleNotice.value!.actionId);
    expect(_tasks(s, 'Buy Duaris cream'), isEmpty);
    expect(s.list('rules').firstWhere((r) => r['name'] == 'Buy Duaris cream')['on'], true);
  });

  test('built-in links start off; rent paid goes into Money once switched on', () async {
    final s = await _store();
    final rent = s.list('rules').firstWhere((r) => r['builtin'] == 'rent');
    expect(rent['on'], false);
    s.list('rooms').add({'id': 900, 'number': '2A'});
    s.list('rentPays').add({'id': 901, 'room': 900, 'amount': 6000, 'paidAt': 0});
    s.save();
    expect(s.list('tx'), isEmpty);

    rent['on'] = true;
    s.save();
    s.list('rentPays').add({'id': 902, 'room': 900, 'amount': 6000, 'paidAt': 0});
    s.save();
    final tx = s.list('tx').single;
    expect(tx['type'], 'income');
    expect(tx['amount'], 6000);
    expect(tx['note'], 'Rent room 2A');
  });

  test('paying a bill ticks off its task', () async {
    final s = await _store();
    s.list('rules').firstWhere((r) => r['builtin'] == 'billDone')['on'] = true;
    s.list('items').add({'id': 950, 'kind': 'task', 'title': 'Pay electricity bill', 'status': 'open'});
    s.list('items').add({'id': 951, 'kind': 'task', 'title': 'Read about electricity', 'status': 'open'});
    s.save();
    s.addTx(type: 'expense', amount: 1200, category: 'Bills', account: 'Cash', note: 'electricity bill');
    expect(s.byId('items', 950)!['status'], 'done');
    expect(s.byId('items', 951)!['status'], 'open');
  });

  test('what a rule does sets off no other rule, so rules cannot loop', () async {
    final s = await _store();
    s.list('rules').add({
      'id': 960, 'name': 'Echo', 'on': true,
      'when': {'on': 'money'},
      'then': [{'do': 'money', 'moneyType': 'income', 'account': 'Cash', 'category': 'Echo'}],
    });
    s.save();
    _income(s, 10);
    expect(s.list('tx').length, 2);
  });

  test('data merged from another device sets off nothing here', () async {
    final s = await _store();
    s.list('rules').add({
      'id': 970, 'name': 'Note income', 'on': true,
      'when': {'on': 'money'},
      'then': [{'do': 'remind', 'text': 'Got {amount}'}],
    });
    s.save();
    final merged = Map<String, dynamic>.from(s.state);
    merged['tx'] = [
      {'id': 971, 'type': 'income', 'amount': 5, 'account': 'Cash', 'cat': 'Other', 'ts': 0},
    ];
    await s.replaceState(merged);
    expect(s.list('rules').firstWhere((r) => r['id'] == 970)['fired'], isNull);
  });
}
