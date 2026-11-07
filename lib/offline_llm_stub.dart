import 'dart:typed_data';

const supported = false;

Future<String?> installed() async => null;

Future<void> download(String id, void Function(int) progress) async =>
    throw UnsupportedError('Offline models run in the Android app.');

Future<void> remove() async {}

Future<String> generate(String prompt, {required bool json, Uint8List? image}) async =>
    throw UnsupportedError('Offline models run in the Android app.');
