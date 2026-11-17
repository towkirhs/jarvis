import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'haptics.dart';
import 'native.dart';
import 'store.dart';

/// Alarm sounds that come with Jarvis, and choosing one (or your own music) for an alarm.
class AlarmSounds {
  static const builtIn = [
    (name: 'Digital alarm', asset: 'assets/sounds/digital-alarm.mp3'),
    (name: 'Digital alarm 2', asset: 'assets/sounds/digital-alarm-2.mp3'),
  ];

  static Future<Directory> _dir() async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/alarm_sounds');
    await dir.create(recursive: true);
    return dir;
  }

  /// A built-in sound as a file the phone's alarm can play (copied out of the app once).
  static Future<String> file(String asset) async {
    final out = File('${(await _dir()).path}/${asset.split('/').last}');
    if (!await out.exists()) {
      final data = await rootBundle.load(asset);
      await out.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }
    return out.path;
  }

  /// Once per phone: "Digital alarm" becomes the alarm sound, unless you already chose one.
  static Future<void> ensureDefault(Store s) async {
    if (kIsWeb || s.local('defaultSound') == '1') return;
    try {
      final prefs = await Native.alarmPrefs();
      if (prefs['sound'] == null) {
        await Native.setAlarmPref('sound', await file(builtIn.first.asset));
        await Native.setAlarmPref('soundName', builtIn.first.name);
      }
      await s.setLocal('defaultSound', '1');
    } catch (_) {
      // Tried again the next time Jarvis opens.
    }
  }
}

/// Picks a sound: a built-in one, your own music, or none of its own ([noneLabel], such as "Your usual alarm sound").
/// Returns null if nothing was picked; a record with a null path means "none of its own".
Future<({String? path, String? name})?> pickAlarmSound(BuildContext context, {required String noneLabel, String? current}) {
  return showModalBottomSheet<({String? path, String? name})>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      Widget option(IconData icon, String title, Future<({String? path, String? name})?> Function() pick, {bool on = false}) => ListTile(
            leading: Icon(icon),
            title: Text(title),
            trailing: on ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary) : null,
            onTap: () async {
              final picked = await pick();
              if (picked != null && ctx.mounted) Navigator.pop(ctx, picked);
            },
          );
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final b in AlarmSounds.builtIn)
              option(Icons.alarm, b.name, () async => (path: await AlarmSounds.file(b.asset), name: b.name), on: current == b.name),
            option(Icons.music_note_outlined, 'Your own music', () async {
              final r = await FilePicker.platform.pickFiles(type: FileType.audio);
              final f = r?.files.single;
              if (f?.path == null) return null;
              // A copy in the app's own folder, so the alarm still rings if the original is moved.
              final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/alarm_sounds');
              await dir.create(recursive: true);
              final copy = await File(f!.path!).copy('${dir.path}/${DateTime.now().millisecondsSinceEpoch}_${f.name}');
              Haptics.success();
              return (path: copy.path, name: f.name.replaceAll(RegExp(r'\.[^.]+$'), ''));
            }),
            option(Icons.phone_android, noneLabel, () async => (path: null, name: null), on: current == null),
          ]),
        ),
      );
    },
  );
}

/// How loud an alarm rings: {vol: 10-100 (% of the phone's alarm volume), rise: gets louder slowly, vib: vibrates}.
class AlarmStyle {
  static String describe(Map? st, {String none = 'Your usual'}) {
    if (st == null || st.isEmpty) return none;
    return [
      st['vol'] is int ? 'Loudness ${st['vol']}%' : "Phone's alarm volume",
      if (st['rise'] == true) 'gets louder slowly',
      st['vib'] == false ? 'no vibration' : 'vibrates',
    ].join(' · ');
  }
}

/// Sets an alarm's intensity. Returns the new style, `{}` for "use my usual" (when [allowUsual]), or null if closed.
Future<Map<String, dynamic>?> pickAlarmStyle(BuildContext context, Map? current, {bool allowUsual = true, String? sound}) {
  var vol = (current?['vol'] as int?) ?? 100;
  var rise = current?['rise'] == true;
  var vib = current?['vib'] != false;
  Map<String, dynamic> style() => {'vol': vol, 'rise': rise, 'vib': vib};
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final tt = Theme.of(ctx).textTheme;
      final scheme = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Intensity', style: tt.headlineSmall),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text('Loudness', style: tt.titleSmall)),
              Text('$vol%', style: tt.titleSmall?.copyWith(color: scheme.primary)),
            ]),
            Row(children: [
              const Icon(Icons.volume_mute),
              Expanded(
                child: Slider(
                  value: vol.toDouble(),
                  min: 10,
                  max: 100,
                  divisions: 9,
                  label: '$vol%',
                  onChanged: (v) {
                    Haptics.segment();
                    setS(() => vol = v.round());
                  },
                ),
              ),
              const Icon(Icons.volume_up),
            ]),
            Text('Of the phone\'s alarm volume, while it rings. Your volume goes back after.',
                style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Get louder slowly'),
              subtitle: const Text('Starts soft, full loudness after about a minute'),
              value: rise,
              onChanged: (v) {
                Haptics.toggle(v);
                setS(() => rise = v);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vibrate'),
              value: vib,
              onChanged: (v) {
                Haptics.toggle(v);
                setS(() => vib = v);
              },
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
              if (allowUsual) TextButton(onPressed: () => Navigator.pop(ctx, <String, dynamic>{}), child: const Text('Use my usual')),
              OutlinedButton(
                onPressed: kIsWeb ? null : () => Native.ringNow('Test alarm', sound, style: jsonEncode(style())),
                child: const Text('Try it'),
              ),
              FilledButton(onPressed: () => Navigator.pop(ctx, style()), child: const Text('Done')),
            ]),
          ]),
        ),
      );
    }),
  );
}
