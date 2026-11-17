import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/brain.dart';
import 'package:jarcis/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('"alarm at 6" in the chat sets a Clock alarm, not an item in the list; Undo removes it', () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('jarcis/native'), (call) async {
      calls.add(call);
      return null;
    });
    final s = Store();
    await s.load();

    await Brain.capture(s, 'alarm at 6');
    final clock = s.list('clocks').single;
    expect([clock['time'], clock['on'], clock['days'], clock['label']], ['06:00', true, <int>[], '']);
    expect(clock['at'], greaterThan(DateTime.now().millisecondsSinceEpoch));
    expect(s.list('items').where((i) => i['kind'] == 'alarm'), isEmpty);
    expect(calls.any((c) => c.method == 'clock' && (c.arguments as Map)['label'] == 'Alarm'), isTrue);

    await Brain.capture(s, 'alarm at 6');
    expect(s.list('clocks'), hasLength(1));
    expect(s.list('captures').last['msg'], startsWith('Already have an alarm'));

    await s.undo(s.list('captures').first['actionId'] as int);
    expect(s.list('clocks'), isEmpty);
  });
}
