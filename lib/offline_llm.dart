import 'dart:typed_data';

import 'offline_llm_stub.dart' if (dart.library.io) 'offline_llm_io.dart' as impl;

/// A model you can download once and run on the phone with no internet.
class OfflineModel {
  const OfflineModel(this.id, this.name, this.size, this.about);
  final String id;
  final String name;
  final String size;
  final String about;
}

/// AI that runs on the phone itself (LiteRT-LM). Android only; one model installed at a time.
class OfflineLlm {
  static const models = [
    OfflineModel('gemma4-e2b', 'Gemma 4 E2B', '2.6 GB',
        'Best: understands Bangla and photos. For phones with 8 GB of memory. A few seconds per note.'),
    OfflineModel('qwen2.5-1.5b', 'Qwen 2.5 1.5B', '1.6 GB', 'Good at tidy JSON, text only. Phones with 6 GB.'),
    OfflineModel('qwen3-0.6b', 'Qwen 3 0.6B', '345 MB', 'Tiny and fast, text only. Fine for simple notes.'),
  ];

  static bool get supported => impl.supported;

  /// The model on the phone (its id), or null.
  static Future<String?> installed() => impl.installed();

  /// Downloads [id] (replacing any other). [progress] gets 0 to 100.
  static Future<void> download(String id, void Function(int) progress) => impl.download(id, progress);

  static Future<void> remove() => impl.remove();

  static Future<String> generate(String prompt, {required bool json, Uint8List? image}) =>
      impl.generate(prompt, json: json, image: image);
}
