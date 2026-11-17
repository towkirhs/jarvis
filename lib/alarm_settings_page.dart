import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'haptics.dart';
import 'native.dart';

/// How alarms and reminders show on this phone: on the full screen or as a notification, the alarm sound
/// used for everything, and whether Android lets Jarvis open over other apps and the lock screen.
class AlarmSettingsPage extends StatefulWidget {
  const AlarmSettingsPage({super.key});

  @override
  State<AlarmSettingsPage> createState() => _AlarmSettingsPageState();
}

class _AlarmSettingsPageState extends State<AlarmSettingsPage> with WidgetsBindingObserver {
  Map<String, dynamic> _p = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from Android's settings: read the permissions again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final p = await Native.alarmPrefs();
    if (mounted) setState(() => _p = p);
  }

  Future<void> _set(String key, Object? value) async {
    await Native.setAlarmPref(key, value);
    await _load();
  }

  Future<void> _pickSound() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.audio);
    final f = r?.files.single;
    if (f?.path == null) return;
    // A copy in the app's own folder, so alarms still ring if the original is moved.
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/alarm_sounds');
    await dir.create(recursive: true);
    final copy = await File(f!.path!).copy('${dir.path}/global_${DateTime.now().millisecondsSinceEpoch}_${f.name}');
    await Native.setAlarmPref('soundName', f.name.replaceAll(RegExp(r'\.[^.]+$'), ''));
    await _set('sound', copy.path);
    Haptics.success();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final canFull = _p['canFullScreen'] != false;
    final overlay = _p['overlay'] != false;
    Widget title(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(text, style: tt.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
        );
    Widget fix(String what, String why, VoidCallback onTap) => Card(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          color: scheme.tertiaryContainer,
          child: ListTile(
            leading: Icon(Icons.warning_amber_rounded, color: scheme.onTertiaryContainer),
            title: Text(what),
            subtitle: Text(why),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Alarms and reminders')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (!overlay)
            fix('Let Jarvis show over other apps', 'Needed for an alarm to take the screen while you use the phone. Tap, then allow it.',
                Native.openOverlaySettings),
          if (!canFull)
            fix('Let Jarvis use the full screen', 'Needed for an alarm to show on a locked phone. Tap, then allow it.',
                Native.openFullScreenSettings),
          title('On the full screen'),
          SwitchListTile(
            title: const Text('Alarms'),
            subtitle: const Text('Every alarm takes the whole screen, with Stop or Done and Snooze, and rings until you answer. '
                'Off: alarms set on a task or event are a notification only.'),
            value: _p['fullAlarm'] != false,
            onChanged: (v) => _set('fullAlarm', v),
          ),
          SwitchListTile(
            title: const Text('Reminders'),
            subtitle: const Text('A reminder also opens on the whole screen, with Done, Snooze and Close. Off: a notification only.'),
            value: _p['fullNotice'] == true,
            onChanged: (v) => _set('fullNotice', v),
          ),
          title('Sound'),
          ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: Text('${_p['soundName'] ?? "The phone's alarm sound"}'),
            subtitle: const Text('The ringtone of every alarm that has no music of its own'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_p['sound'] != null)
                IconButton(
                  tooltip: "Use the phone's alarm sound",
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    await Native.setAlarmPref('soundName', null);
                    await _set('sound', null);
                  },
                ),
              TextButton(onPressed: _pickSound, child: const Text('Choose')),
            ]),
          ),
          title('Try it'),
          ListTile(
            leading: const Icon(Icons.alarm_on_outlined),
            title: const Text('Ring a test alarm now'),
            onTap: () => Native.ringNow('Test alarm', null),
          ),
          ListTile(
            leading: const Icon(Icons.lock_clock_outlined),
            title: const Text('Ring one in 1 minute'),
            subtitle: const Text('Lock the phone or open another app, to see it take the screen'),
            onTap: () async {
              await Native.clock(id: DateTime.now().millisecondsSinceEpoch % 1000000000, millis: DateTime.now().millisecondsSinceEpoch + 60000, label: 'Test alarm');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A test alarm will ring in 1 minute.')));
              }
            },
          ),
        ],
      ),
    );
  }
}
