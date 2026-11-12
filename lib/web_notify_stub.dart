bool get webNotifySupported => false;
String webNotifyPermission() => 'unsupported';
Future<String> webNotifyAsk() async => 'unsupported';
void webNotify(String title, String body) {}
