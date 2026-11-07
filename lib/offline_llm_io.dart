import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool get supported => Platform.isAndroid;

const _key = 'offline_model';

LiteRtLmVariant _variant(String id) => switch (id) {
      'qwen2.5-1.5b' => LiteRtLmModels.qwen2_5_1_5bInstruct.q8Ekv4096,
      'qwen3-0.6b' => LiteRtLmModels.qwen3_0_6b.dynamicInt4,
      _ => LiteRtLmModels.gemma4E2bIt.generic,
    };

bool _ready = false;
InferenceModel? _model;
String? _loaded;

Future<void> _init() async {
  if (_ready) return;
  await FlutterEdgeAi.initialize(inferenceEngines: [LiteRtLmEngine()]);
  _ready = true;
}

Future<String?> installed() async {
  if (!supported) return null;
  final id = (await SharedPreferences.getInstance()).getString(_key);
  if (id == null) return null;
  await _init();
  final file = _variant(id).file?.installFilename;
  return file != null && await FlutterEdgeAi.isModelInstalled(file) ? id : null;
}

Future<void> download(String id, void Function(int) progress) async {
  await _init();
  final old = await installed();
  if (old != null && old != id) await remove();
  await FlutterEdgeAi.installModelFromCatalog(_variant(id)).withProgress(progress).install();
  await (await SharedPreferences.getInstance()).setString(_key, id);
}

Future<void> remove() async {
  await _init();
  await _model?.close();
  _model = null;
  _loaded = null;
  final prefs = await SharedPreferences.getInstance();
  final id = prefs.getString(_key);
  final file = id == null ? null : _variant(id).file?.installFilename;
  if (file != null) await FlutterEdgeAi.uninstallModel(file);
  await prefs.remove(_key);
}

Future<String> generate(String prompt, {required bool json, Uint8List? image}) async {
  final id = await installed();
  if (id == null) throw Exception('No offline model downloaded.');
  final variant = _variant(id);
  // Keep the model loaded between notes; loading is the slow part.
  if (_model == null || _model!.isClosed || _loaded != id) {
    await _model?.close();
    _model = await FlutterEdgeAi.getActiveModel(defaults: variant.runtimeDefaults, maxTokens: 4096);
    _loaded = id;
  }
  final session = await _model!.createSession(
    temperature: json ? 0.1 : 0.4,
    enableVisionModality: image != null && id == 'gemma4-e2b',
  );
  try {
    // Qwen 3 thinks out loud unless told not to.
    final text = id == 'qwen3-0.6b' ? '$prompt /no_think' : prompt;
    await session.addQueryChunk(image != null && id == 'gemma4-e2b'
        ? Message.withImage(text: text, imageBytes: image, isUser: true)
        : Message.text(text: text, isUser: true));
    var out = (await session.getResponse()).replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
    if (json) {
      final start = out.indexOf('{');
      final end = out.lastIndexOf('}');
      if (start >= 0 && end > start) out = out.substring(start, end + 1);
    }
    return out;
  } finally {
    await session.close();
  }
}
