import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/memory.dart';

void main() {
  const t0 = 1000000000000;
  var id = 0;
  int nextId() => ++id;
  List<Map<String, dynamic>> mems() => <Map<String, dynamic>>[];

  group('merge', () {
    test('a new fact is added, a repeated one is counted', () {
      final m = mems();
      expect(Memory.merge(m, ['Supports Manchester United', 'Oishi is their sister'], now: t0, nextId: nextId), 2);
      expect(Memory.merge(m, ['Supports Manchester United.'], now: t0 + 5, nextId: nextId), 0);
      expect(m.length, 2);
      expect(m.first['n'], 2);
      expect(m.first['last'], t0 + 5);
    });
    test('the same fact in other words is the same fact', () {
      expect(Memory.same('Supports Man United', 'Supports Man United team'), isTrue);
      expect(Memory.same('Goes to the gym at 6 am', 'Goes to the gym at 7 am'), isFalse);
      expect(Memory.same('Oishi is their sister', 'Oishi is their girlfriend'), isFalse);
      expect(Memory.same('Gym at 6 am on weekdays', 'Supports Manchester United'), isFalse);
    });
    test('said twice in one note counts once', () {
      final m = mems();
      Memory.merge(m, ['Studies physics'], now: t0, nextId: nextId);
      Memory.merge(m, ['Studies physics', 'studies physics'], now: t0, nextId: nextId);
      expect(m.single['n'], 2);
    });
    test('secrets, noise and long text are not kept like that', () {
      final m = mems();
      Memory.merge(m, ['Their password is hunter2', 'ok', '', null, 'Card 4111 1111 1111 1111'], now: t0, nextId: nextId);
      expect(m, isEmpty);
      expect(Memory.clean('x' * 300)!.length, Memory.maxText);
    });
    test('over the limit, the least used unpinned ones go', () {
      final m = mems();
      for (var i = 0; i < Memory.maxKept; i++) {
        m.add({'id': 5000 + i, 'text': 'fact number ${i}x', 'ts': t0, 'last': t0 + i, 'n': 1, 'pin': i == 0});
      }
      m[1]['n'] = 5;
      Memory.merge(m, ['Brand new lasting fact about robots'], now: t0 + 999, nextId: nextId);
      expect(m.length, Memory.maxKept);
      expect(m.any((x) => x['id'] == 5000), isTrue); // pinned
      expect(m.any((x) => x['id'] == 5001), isTrue); // often seen
      expect(m.any((x) => x['id'] == 5002), isFalse); // oldest, seen once
      expect(m.any((x) => x['text'] == 'Brand new lasting fact about robots'), isTrue);
    });
  });

  group('pick', () {
    List<Map<String, dynamic>> sample() => [
          {'id': 1, 'text': 'Supports Manchester United', 'ts': t0, 'last': t0, 'n': 1, 'pin': false},
          {'id': 2, 'text': 'Oishi is their sister', 'ts': t0, 'last': t0, 'n': 1, 'pin': false},
          {'id': 3, 'text': 'Goes to the gym at 6 am on weekdays', 'ts': t0, 'last': t0, 'n': 6, 'pin': false},
          {'id': 4, 'text': 'Lives in Dhaka', 'ts': t0, 'last': t0, 'n': 1, 'pin': true},
          {'id': 5, 'text': 'Studies physics at university', 'ts': t0, 'last': t0, 'n': 1, 'pin': false},
        ];

    test('pinned, relevant and often repeated facts come; the rest stay out', () {
      final out = Memory.pick(sample(), 'any match today of manchester united');
      expect(out, containsAll(['Supports Manchester United', 'Lives in Dhaka', 'Goes to the gym at 6 am on weekdays']));
      expect(out, isNot(contains('Oishi is their sister')));
      expect(out, isNot(contains('Studies physics at university')));
    });
    test('the closest match comes first and the size is capped', () {
      final out = Memory.pick(sample(), 'call oishi', maxChars: 40);
      expect(out.first, 'Lives in Dhaka'); // pinned first
      expect(out.join().length, lessThanOrEqualTo(40));
      expect(Memory.pick(sample(), 'call oishi').indexOf('Oishi is their sister'),
          lessThan(Memory.pick(sample(), 'call oishi').indexOf('Goes to the gym at 6 am on weekdays')));
    });
    test('no memories, no problem', () {
      expect(Memory.pick([], 'hello there'), isEmpty);
    });
  });
}
