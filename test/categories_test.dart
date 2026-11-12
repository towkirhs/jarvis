import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/categories.dart';

void main() {
  Map<String, dynamic> tx(String type, String cat, num amount) => {'type': type, 'cat': cat, 'amount': amount};

  test('a new entry takes the spelling already in use, whatever the case', () {
    final known = ['Food', 'food', 'Bills'];
    expect(Cats.tidy('food', type: 'expense', rules: {}, known: known), 'Food');
    expect(Cats.tidy(' BILLS ', type: 'expense', rules: {}, known: known), 'Bills');
  });

  test('a new name starts with a capital', () {
    expect(Cats.tidy('hackathon', type: 'expense', rules: {}, known: ['Food']), 'Hackathon');
  });

  test('a rule maps one name to another, for that type only', () {
    final rules = {'expense:groceries': 'Food'};
    expect(Cats.tidy('Groceries', type: 'expense', rules: rules, known: ['Food']), 'Food');
    expect(Cats.tidy('groceries', type: 'income', rules: rules, known: []), 'Groceries');
  });

  test('a rule that points at another rule is followed, and a loop cannot hang', () {
    expect(Cats.tidy('a', type: 'expense', rules: {'expense:a': 'B', 'expense:b': 'C'}, known: []), 'C');
    expect(Cats.tidy('a', type: 'expense', rules: {'expense:a': 'B', 'expense:b': 'A'}, known: []), isNotEmpty);
  });

  test('an empty name stays empty so the caller can use Other', () {
    expect(Cats.tidy('  ', type: 'expense', rules: {}, known: []), '');
  });

  test('names are listed most used first, and counted per type', () {
    final txs = [tx('expense', 'Food', 100), tx('expense', 'food', 50), tx('expense', 'Food', 30), tx('income', 'Salary', 9)];
    final used = Cats.used(txs, 'expense');
    expect(used.map((e) => e.name), ['Food', 'food']);
    expect((used.first.count, used.first.total), (2, 130));
  });

  test('names that differ only by case or spaces are offered for merging', () {
    final txs = [tx('expense', 'Food', 1), tx('expense', 'food ', 1), tx('expense', 'Food', 1), tx('expense', 'Bills', 1)];
    final groups = Cats.lookAlikes(Cats.used(txs, 'expense'));
    expect(groups.length, 1);
    expect(groups.first.map((e) => e.name), ['Food', 'food ']);
  });

  test('merging moves every entry of that type and keeps a rule, and re-points older rules', () {
    final txs = [tx('expense', 'groceries', 10), tx('income', 'groceries', 5), tx('expense', 'Food', 1)];
    final rules = <String, dynamic>{'expense:veg': 'groceries'};
    final moved = Cats.merge(txs, rules, 'expense', 'groceries', 'Food');
    expect(moved, 1);
    expect(txs.map((t) => t['cat']), ['Food', 'groceries', 'Food']);
    expect(rules, {'expense:groceries': 'Food', 'expense:veg': 'Food'});
  });

  test('merging a name into itself changes nothing', () {
    final txs = [tx('expense', 'Food', 1)];
    final rules = <String, dynamic>{};
    expect(Cats.merge(txs, rules, 'expense', 'Food', 'Food'), 0);
    expect(rules, isEmpty);
  });
}
