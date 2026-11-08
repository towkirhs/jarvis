import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'native.dart';
import 'store.dart';

/// Updates Jarvis from its GitHub releases, inside the app.
class Updater {
  static const _repo = 'https://github.com/towkirhs/jarvis';

  /// "…/releases/tag/build-115" → 115.
  static int? buildOf(String url) => int.tryParse(RegExp(r'/tag/build-(\d+)').firstMatch(url)?[1] ?? '');

  /// The newest release's build number. Read from where the releases page points, not from GitHub's API,
  /// so it is not rate limited like Obtainium.
  static Future<int?> latest() async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse('$_repo/releases/latest'))..followRedirects = false;
      final res = await client.send(req).timeout(const Duration(seconds: 20));
      return buildOf(res.headers['location'] ?? '');
    } finally {
      client.close();
    }
  }

  /// Downloads build [n]'s APK, telling [progress] how far along it is (0 to 1).
  static Future<String> download(int n, void Function(double) progress) async {
    final client = http.Client();
    try {
      final res = await client
          .send(http.Request('GET', Uri.parse('$_repo/releases/download/build-$n/jarcis.apk')))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw 'GitHub said ${res.statusCode}';
      final file = File('${(await getTemporaryDirectory()).path}/jarvis-update.apk');
      final sink = file.openWrite();
      var got = 0;
      final total = res.contentLength ?? 0;
      try {
        await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) progress(got / total);
        }
      } finally {
        await sink.close();
      }
      return file.path;
    } finally {
      client.close();
    }
  }

  /// Checks once a day when Jarvis opens; if there is a newer build, offers it at the bottom of the screen.
  static Future<void> checkDaily(BuildContext context, Store s) async {
    if (kIsWeb) return;
    final last = int.tryParse(s.local('update_checked') ?? '') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < const Duration(hours: 20).inMilliseconds) return;
    try {
      final have = await Native.appBuild();
      final n = await latest();
      await s.setLocal('update_checked', '$now');
      if (n == null || n <= have || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Jarvis build $n is ready.'),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(label: 'Update', onPressed: () => run(context, n)),
      ));
    } catch (_) {
      // Offline or GitHub is slow: try again next time.
    }
  }

  /// Looks for an update and, if there is one, offers to install it.
  static Future<void> check(BuildContext context) async {
    void say(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
    try {
      final have = await Native.appBuild();
      final n = await latest();
      if (!context.mounted) return;
      if (n == null) return say("Couldn't read the latest release from GitHub.");
      if (n <= have) return say('Jarvis is up to date (build $have).');
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Build $n is ready'),
          content: Text('${have > 1 ? 'You have build $have. ' : ''}It downloads about 75 MB, then Android asks you to confirm.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Update')),
          ],
        ),
      );
      if (go == true && context.mounted) await run(context, n);
    } catch (e) {
      if (context.mounted) say("Couldn't check for updates: $e");
    }
  }

  /// Downloads build [n] with a progress bar, then hands it to Android's installer.
  static Future<void> run(BuildContext context, int n) async {
    void say(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
    if (!await Native.canInstall()) {
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Allow Jarvis to update itself'),
          content: const Text('Android needs your OK once. Turn on "Allow from this source", come back, and tap Update again.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open settings')),
          ],
        ),
      );
      if (ok == true) await Native.openInstallAccess();
      return;
    }
    if (!context.mounted) return;
    final progress = ValueNotifier<double?>(null);
    final nav = Navigator.of(context);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Downloading build $n'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, v, __) => Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: v),
            const SizedBox(height: 8),
            Text(v == null ? 'Starting…' : '${(v * 100).round()}%'),
          ]),
        ),
      ),
    ));
    try {
      final path = await download(n, (v) => progress.value = v);
      nav.pop();
      final err = await Native.installApk(path);
      if (err != null && context.mounted) say("Couldn't start the update: $err");
    } catch (e) {
      nav.pop();
      if (context.mounted) say('Download failed: $e. Try again later.');
    }
  }
}
