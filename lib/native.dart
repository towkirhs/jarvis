import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Thin wrapper over the Android side (alarms, reminders, shared text). Does nothing on the web.
class Native {
  static const _ch = MethodChannel('jarcis/native');
  static void Function(String text)? onShared;
  static void Function()? onNotesWaiting;
  static void Function()? onDoneWaiting;
  static void Function()? onMoneyWaiting;
  static void Function(String action)? onLaunchAction;

  static void init() {
    if (kIsWeb) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'sharedText') onShared?.call(call.arguments as String);
      if (call.method == 'notesWaiting') onNotesWaiting?.call();
      if (call.method == 'doneWaiting') onDoneWaiting?.call();
      if (call.method == 'moneyWaiting') onMoneyWaiting?.call();
      if (call.method == 'launchAction') onLaunchAction?.call(call.arguments as String);
      return null;
    });
  }

  static Future<String?> takeSharedText() async =>
      kIsWeb ? null : await _ch.invokeMethod<String>('takeSharedText');

  /// Dictations sent by the Handy app while Jarvis was closed.
  /// Notes sent from Handy or the share menu while Jarvis was closed, as (text, image path or null, source).
  static Future<List<(String, String?, String)>> takeNotes() async {
    if (kIsWeb) return [];
    final raw = await _ch.invokeMethod<String>('takeNotes');
    if (raw == null) return [];
    return [
      for (final e in jsonDecode(raw) as List)
        e is Map
            ? ((e['text'] as String?) ?? '', e['image'] as String?, (e['source'] as String?) ?? 'handy')
            : (e.toString(), null, 'handy'),
    ];
  }

  /// What Handy's Jarvis bubble asked to open ('text' or 'photo'), if the app was started for that.
  static Future<String?> takeLaunchAction() async =>
      kIsWeb ? null : await _ch.invokeMethod<String>('takeLaunchAction');

  /// Money SMS and notifications waiting to be read, as (sender, text, received at).
  static Future<List<(String, String, int)>> takeMoney() async {
    if (kIsWeb) return [];
    final raw = await _ch.invokeMethod<String>('takeMoney');
    if (raw == null) return [];
    return [
      for (final e in jsonDecode(raw) as List)
        ((e['from'] as String?) ?? '', (e['text'] as String?) ?? '', (e['ts'] as num).toInt()),
    ];
  }

  /// Whether Jarvis may read SMS and notifications for money logging.
  static Future<({bool sms, bool notifications})> moneyAccess() async {
    if (kIsWeb) return (sms: false, notifications: false);
    final m = await _ch.invokeMapMethod<String, bool>('moneyAccess') ?? {};
    return (sms: m['sms'] ?? false, notifications: m['notifications'] ?? false);
  }

  static Future<void> requestSmsPermission() async {
    if (!kIsWeb) await _ch.invokeMethod('requestSmsPermission');
  }

  static Future<void> openNotificationAccess() async {
    if (!kIsWeb) await _ch.invokeMethod('openNotificationAccess');
  }

  /// Notification ids the person tapped Done on.
  static Future<List<int>> takeDone() async {
    if (kIsWeb) return [];
    final raw = await _ch.invokeMethod<String>('takeDone');
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => (e as num).toInt()).toList();
  }

  /// Tells Android the background run is finished, so it can shut down.
  static Future<void> backgroundDone() => _ch.invokeMethod('backgroundDone');

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
