/// Browser notifications for the web app; does nothing on the phone (Android has real alarms).
export 'web_notify_stub.dart' if (dart.library.js_interop) 'web_notify_web.dart';
