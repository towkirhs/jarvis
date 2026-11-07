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

  // ---------- alarm clock and places ----------

  /// An alarm from the Clock page at [millis], repeating on the weekdays in [days] (Monday = bit 0; 0 = once),
  /// ringing with the music file at [sound] (or the phone's alarm sound).
  static Future<void> clock({required int id, required int millis, required String label, int days = 0, String? sound}) async {
    if (!kIsWeb) await _ch.invokeMethod('clock', {'id': id, 'millis': millis, 'label': label, 'days': days, 'sound': sound});
  }

  /// Rings straight away, to try an alarm's sound.
  static Future<void> ringNow(String label, String? sound) async {
    if (!kIsWeb) await _ch.invokeMethod('ringNow', {'label': label, 'sound': sound});
  }

  /// Replaces the place triggers the phone watches.
  static Future<void> geofences(String json) async {
    if (!kIsWeb) await _ch.invokeMethod('geofences', {'json': json});
  }

  /// Keys of one-time place alarms that went off since the last call.
  static Future<List<String>> takeGeoFired() async {
    if (kIsWeb) return [];
    return (jsonDecode(await _ch.invokeMethod<String>('takeGeoFired') ?? '[]') as List).cast<String>();
  }

  /// {fine, background}: location allowed while using the app, and all the time (needed for places).
  static Future<Map<String, bool>> locationAccess() async {
    if (kIsWeb) return {};
    final m = await _ch.invokeMethod<Map>('locationAccess');
    return {for (final e in (m ?? {}).entries) '${e.key}': e.value == true};
  }

  /// Asks for location: first "while using the app", then (called again) "all the time".
  static Future<void> requestLocation() async {
    if (!kIsWeb) await _ch.invokeMethod('requestLocation');
  }

  /// Where the phone is now, or null.
  static Future<(double, double)?> here() async {
    if (kIsWeb) return null;
    final m = await _ch.invokeMethod<Map>('here');
    return m == null ? null : ((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble());
  }

  /// Opens a web page in the phone's browser.
  static Future<void> openUrl(String url) async {
    if (kIsWeb) return;
    await _ch.invokeMethod('openUrl', {'url': url});
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

  // ---------- phone actions and "Jarvis" wake word ----------

  /// Runs a phone action ("open WhatsApp", "call Oishi on WhatsApp") and says what happened, or returns null
  /// when the text is an ordinary note.
  static Future<String?> command(String text) async {
    if (kIsWeb) return null;
    try {
      return await _ch.invokeMethod<String>('command', {'text': text});
    } catch (_) {
      return null;
    }
  }

  /// Nicknames, app names and your own phrases, for the phone side to use.
  static Future<void> setShortcuts(String json) async {
    if (!kIsWeb) await _ch.invokeMethod('setShortcuts', {'json': json});
  }

  /// Commands done by voice while the app was closed: (what you said, what happened, when).
  static Future<List<(String, String, int)>> takeCommandLog() async {
    if (kIsWeb) return [];
    final raw = await _ch.invokeMethod<String>('takeCommandLog');
    return [
      for (final e in (jsonDecode(raw ?? '[]') as List).cast<Map>())
        ('${e['said']}', '${e['did']}', (e['ts'] as num).toInt()),
    ];
  }

  /// Starts or stops listening for "Hey Jarvis". [threshold] (0 to 1): lower hears it more easily.
  static Future<void> wake(bool on, {double? threshold}) async {
    if (!kIsWeb) await _ch.invokeMethod('wake', {'on': on, 'threshold': threshold});
  }

  static Future<Map<String, bool>> voiceAccess() async {
    if (kIsWeb) return {};
    final m = await _ch.invokeMethod<Map>('voiceAccess');
    return {for (final e in (m ?? {}).entries) '${e.key}': e.value == true};
  }

  static Future<void> requestVoicePermissions() async {
    if (!kIsWeb) await _ch.invokeMethod('requestVoicePermissions');
  }

  static Future<void> openOverlaySettings() async {
    if (!kIsWeb) await _ch.invokeMethod('openOverlaySettings');
  }

  /// Notification ids the person tapped Done on.
  static Future<List<int>> takeDone() async {
    if (kIsWeb) return [];
    final raw = await _ch.invokeMethod<String>('takeDone');
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => (e as num).toInt()).toList();
  }

  /// Shows Jarvis's reply to a note as a notification (replaces the previous reply).
  static Future<void> notify(String title, String text) async {
    if (kIsWeb) return;
    try {
      await _ch.invokeMethod('notify', {'title': title, 'text': text});
    } catch (_) {
      // An older install without this method: the reply is still in the app.
    }
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
