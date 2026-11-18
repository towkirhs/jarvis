import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import 'store.dart';

/// Backups as files: one a day kept on the phone (the last [keep]), a copy you save anywhere, and restoring.
/// A backup is everything in Jarvis except AI keys (they live outside the saved data).
class Backups {
  static const keep = 14;

  /// File name of the daily backup of [day] ("YYYY-MM-DD").
  static String name(String day) => 'jarvis-$day.json';

  /// The day a backup file is from, or null if the name is not one of ours.
  static String? dayOf(String fileName) => RegExp(r'^jarvis-(\d{4}-\d{2}-\d{2})\.json$').firstMatch(fileName)?[1];

  /// Of the daily backup file names, the ones to delete: all but the newest [keep].
  static List<String> extra(List<String> names) {
    final ours = names.where((n) => dayOf(n) != null).toList()..sort();
    return ours.length <= keep ? const [] : ours.sublist(0, ours.length - keep);
  }

  /// "12 tasks, 4 habits, 230 money entries, 40 journal entries": what a backup holds.
  static String summary(Map data) {
    int n(String col) => (data[col] as List?)?.length ?? 0;
    final tasks = ((data['items'] as List?) ?? const []).length;
    return '$tasks tasks and events, ${n('habits')} habits, ${n('tx')} money entries, ${n('entries')} journal entries';
  }

  /// Reads backup text: the data, or a FormatException if it is not a Jarvis backup.
  static Map<String, dynamic> parse(String text) {
    final data = jsonDecode(text);
    if (data is! Map<String, dynamic> || data['items'] is! List || data['captures'] is! List) {
      throw const FormatException('Not a Jarvis backup');
    }
    return data;
  }

  static Future<Directory> dir() async {
    final d = Directory('${(await getApplicationDocumentsDirectory()).path}/backups');
    await d.create(recursive: true);
    return d;
  }

  /// Once a day: today's backup file, and the oldest ones beyond [keep] removed.
  static Future<void> daily(Store s) async {
    if (kIsWeb) return;
    final d = await dir();
    final f = File('${d.path}/${name(DayStart.today())}');
    if (await f.exists()) return;
    await f.writeAsString(s.exportBackup(), flush: true);
    final names = d.listSync().whereType<File>().map((x) => x.uri.pathSegments.last).toList();
    for (final old in extra(names)) {
      await File('${d.path}/$old').delete();
    }
  }

  /// The daily backups, newest first.
  static Future<List<File>> list() async {
    if (kIsWeb) return const [];
    final d = await dir();
    return d.listSync().whereType<File>().where((f) => dayOf(f.uri.pathSegments.last) != null).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
  }

  /// Keeps what is on the phone now before a restore replaces it.
  static Future<void> beforeRestore(Store s) async {
    if (kIsWeb) return;
    final d = await dir();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    await File('${d.path}/before-restore-$stamp.json').writeAsString(s.exportBackup(), flush: true);
  }

  /// Saves a backup where you choose (Downloads, Drive…) through Android's Save dialog. True if saved.
  static Future<bool> saveCopy(Store s) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Jarvis backup',
      fileName: name(DayStart.today()),
      bytes: utf8.encode(s.exportBackup()),
    );
    return path != null;
  }

  /// Picks a backup file and returns its text, or null if none was picked.
  static Future<String?> pick() async {
    final r = await FilePicker.platform.pickFiles(withData: true);
    final f = r?.files.single;
    if (f == null) return null;
    if (f.bytes != null) return utf8.decode(f.bytes!);
    return f.path == null ? null : File(f.path!).readAsString();
  }
}
