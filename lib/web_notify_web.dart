import 'dart:js_interop';

@JS('Notification')
external JSAny? get _notificationClass;

@JS('Notification')
extension type _Notification._(JSObject _) implements JSObject {
  external factory _Notification(String title, [_Options? options]);
  external static String get permission;
  external static JSPromise<JSString> requestPermission();
}

extension type _Options._(JSObject _) implements JSObject {
  external factory _Options({String body, String icon, String tag});
}

bool get webNotifySupported => _notificationClass != null;

/// 'granted', 'denied', 'default' (not asked yet) or 'unsupported'.
String webNotifyPermission() => webNotifySupported ? _Notification.permission : 'unsupported';

Future<String> webNotifyAsk() async {
  if (!webNotifySupported) return 'unsupported';
  return (await _Notification.requestPermission().toDart).toDart;
}

void webNotify(String title, String body) {
  if (webNotifyPermission() != 'granted') return;
  _Notification(title, _Options(body: body, icon: 'icons/Icon-192.png', tag: '$title $body'));
}
