import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Thin wrapper over the Android side (alarms, reminders, shared text). Does nothing on the web.
class Native {
  static const _ch = MethodChannel('jarcis/native');
  static void Function(String text)? onShared;

  static void init() {
    if (kIsWeb) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'sharedText') onShared?.call(call.arguments as String);
      return null;
    });
  }

  static Future<String?> takeSharedText() async =>
      kIsWeb ? null : await _ch.invokeMethod<String>('takeSharedText');

  static Future<void> requestNotificationPermission() async {
    if (!kIsWeb) await _ch.invokeMethod('requestNotificationPermission');
  }

  /// kind is 'alarm' (rings like an alarm clock) or 'notice' (quiet reminder).
  static Future<void> schedule({
    required int id,
    required int millis,
    required String kind,
    required String label,
    bool repeatDaily = false,
  }) async {
    if (kIsWeb) return;
    await _ch.invokeMethod('schedule', {
      'id': id,
      'millis': millis,
      'kind': kind,
      'label': label,
      'repeatDaily': repeatDaily,
    });
  }

  static Future<void> cancel(int id) async {
    if (!kIsWeb) await _ch.invokeMethod('cancel', {'id': id});
  }

  static Future<String> getLog() async =>
      kIsWeb ? '' : (await _ch.invokeMethod<String>('getLog')) ?? '';
}
