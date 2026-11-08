import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/updater.dart';

void main() {
  test('reads the build number from where the latest release points', () {
    expect(Updater.buildOf('https://github.com/towkirhs/jarvis/releases/tag/build-115'), 115);
    expect(Updater.buildOf('https://github.com/towkirhs/jarvis/releases'), isNull);
    expect(Updater.buildOf(''), isNull);
  });
}
