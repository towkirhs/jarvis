import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/rules.dart';

class _F implements RuleFacts {
  _F({this.cash = 0, this.food = 0, this.gym = false, DateTime? at}) : now = at ?? DateTime(2026, 11, 14, 10); // a Saturday
  final num cash;
  final num food;
  final bool gym;
  @override
  final DateTime now;
  @override
  num? balance(String account) => account.toLowerCase() == 'cash' ? cash : null;
  @override
  num spent(String? category, DateTime from) => category == null || category == 'Food' ? food : 0;
  @override
  bool habitDone(String habit) => habit == 'Gym' && gym;
  @override
  bool taskOpen(String text) => text == 'electricity';
}

const income = RuleEvent('money', {'moneyType': 'income', 'amount': 800, 'account': 'Cash', 'category': 'Tuition', 'note': ''});

void main() {
  test('new money, rent, loans, done tasks and done habit days are found by comparing saves', () {
    bool done(Map h, String day) => (h['logs'] as Map)[day] == 'yes';
    final before = <String, dynamic>{
      'tx': [{'id': 1, 'type': 'expense', 'amount': 50, 'account': 'Cash', 'cat': 'Food'}],
      'items': [{'id': 5, 'kind': 'task', 'title': 'Pay electricity bill', 'status': 'open'}],
      'habits': [{'id': 9, 'name': 'Gym', 'logs': {}}],
    };
    final after = <String, dynamic>{
      'tx': [...before['tx'] as List, {'id': 2, 'type': 'income', 'amount': 800, 'account': 'Cash', 'cat': 'Tuition'}],
      'items': [{'id': 5, 'kind': 'task', 'title': 'Pay electricity bill', 'status': 'done'}],
      'habits': [{'id': 9, 'name': 'Gym', 'logs': {'2026-11-14': 'yes'}}],
      'rooms': [{'id': 3, 'number': '2A'}],
      'rentPays': [{'id': 4, 'room': 3, 'amount': 6000}],
      'loanPeople': [{'id': 7, 'name': 'Rahim'}],
      'loans': [{'id': 8, 'person': 7, 'type': 'gave', 'amount': 1000}],
    };
    final events = Rules.happened(Rules.seen(before, habitDone: done), Rules.seen(after, habitDone: done), after);
    final kinds = events.map((e) => e.kind).toSet();
    expect(kinds, {'money', 'task_done', 'habit', 'rent', 'loan'});
    expect(events.firstWhere((e) => e.kind == 'rent').data['room'], '2A');
    expect(events.firstWhere((e) => e.kind == 'loan').data['person'], 'Rahim');
    expect(events.firstWhere((e) => e.kind == 'money').data['amount'], 800);
  });

  test('a money rule matches its type and account only', () {
    final r = {'when': {'on': 'money', 'moneyType': 'income', 'account': 'cash'}};
    expect(Rules.matches(r, income), true);
    expect(Rules.matches(r, const RuleEvent('money', {'moneyType': 'expense', 'amount': 5, 'account': 'Cash'})), false);
    expect(Rules.matches(r, const RuleEvent('money', {'moneyType': 'income', 'amount': 5, 'account': 'Bank'})), false);
    expect(Rules.matches({'when': {'on': 'money', 'min': 1000}}, income), false);
  });

  test('conditions: balance, spending, days, times, habits', () {
    Map rule(List c) => {'if': c};
    expect(Rules.holds(rule([{'check': 'balance', 'account': 'Cash', 'atLeast': 500}]), _F(cash: 700)), true);
    expect(Rules.holds(rule([{'check': 'balance', 'account': 'Cash', 'atLeast': 500}]), _F(cash: 300)), false);
    expect(Rules.holds(rule([{'check': 'balance', 'account': 'Nowhere', 'atLeast': 0}]), _F()), false);
    expect(Rules.holds(rule([{'check': 'spent', 'category': 'Food', 'below': 5000}]), _F(food: 4000)), true);
    expect(Rules.holds(rule([{'check': 'days', 'days': [6, 7]}]), _F()), true);
    expect(Rules.holds(rule([{'check': 'between', 'from': '18:00', 'to': '22:00'}]), _F()), false);
    expect(Rules.holds(rule([{'check': 'between', 'from': '22:00', 'to': '11:00'}]), _F()), true);
    expect(Rules.holds(rule([{'check': 'habit_done', 'habit': 'Gym', 'not': true}]), _F(gym: false)), true);
    expect(Rules.holds(rule([{'check': 'task_open', 'text': 'electricity'}]), _F()), true);
  });

  test('texts take what happened', () {
    expect(Rules.fill('Got {amount} from {category}', income), 'Got 800 from Tuition');
  });

  test('a time rule is due once when its time passes on one of its days', () {
    final r = {'when': {'on': 'time', 'at': '21:00', 'days': [6]}};
    expect(Rules.dueAt(r, DateTime(2026, 11, 14, 20, 59), DateTime(2026, 11, 14, 21, 0)), true);
    expect(Rules.dueAt(r, DateTime(2026, 11, 14, 21, 0), DateTime(2026, 11, 14, 21, 1)), false);
    expect(Rules.dueAt(r, DateTime(2026, 11, 15, 20, 59), DateTime(2026, 11, 15, 21, 0)), false);
  });

  test('a rule from an AI is checked and described', () {
    final (r, why) = Rules.fromAi({
      'when': {'on': 'money', 'moneyType': 'income', 'account': 'Cash'},
      'if': [{'check': 'balance', 'account': 'Cash', 'atLeast': 500}],
      'then': [{'do': 'task', 'title': 'Buy Duaris cream', 'day': 0}],
      'once': true,
    });
    expect(why, isNull);
    expect(Rules.describe({...r!, 'name': 'Cream'}),
        'When income is added to Cash, if Cash has at least 500: add task "Buy Duaris cream" (once).');
    expect(Rules.fromAi({'when': {'on': 'money'}, 'then': []}).$2, isNotNull);
    expect(Rules.fromAi({'when': {'on': 'someday'}, 'then': [{'do': 'remind', 'text': 'x'}]}).$2, isNotNull);
  });
}
