import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'clock.dart';
import 'focus_screen.dart';
import 'haptics.dart';
import 'native.dart';
import 'place_picker.dart';
import 'store.dart';

/// Clock: your alarms (at a time or at a place) and the focus timer.
class ClockScreen extends StatelessWidget {
  const ClockScreen({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Clock'),
            bottom: const TabBar(tabs: [Tab(text: 'Alarms'), Tab(text: 'Focus')]),
          ),
          body: TabBarView(children: [AlarmsTab(store: store), FocusScreen(store: store)]),
        ),
      );
}

class AlarmsTab extends StatelessWidget {
  const AlarmsTab({super.key, required this.store});
  final Store store;

  Future<void> _add(BuildContext context) async {
    final atPlace = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('At a time'),
            subtitle: const Text('Wake up, once or on chosen days'),
            onTap: () => Navigator.pop(ctx, false),
          ),
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: const Text('At a place'),
            subtitle: const Text('Rings when you arrive or leave, like your bus stop'),
            onTap: () => Navigator.pop(ctx, true),
          ),
        ]),
      ),
    );
    if (atPlace != null && context.mounted) await showAlarmEditor(context, store, atPlace: atPlace);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addAlarm',
        onPressed: () => _add(context),
        icon: const Icon(Icons.add_alarm),
        label: const Text('Alarm'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final clocks = store.list('clocks');
          final places = store.list('places');
          final now = DateTime.now();
          DateTime? soonest;
          for (final c in clocks) {
            if (c['on'] != true || c['time'] == null) continue;
            final t = Clock.next(c['time'] as String, Clock.days(c), now);
            if (soonest == null || t.isBefore(soonest)) soonest = t;
          }
          if (clocks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No alarms yet. Add one at a time, with your own music, or at a place: '
                  'it rings when you get there.',
                  textAlign: TextAlign.center,
                  style: tt.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text(
                soonest == null ? 'No time alarm is on' : 'Next alarm ${Clock.until(soonest, now)}',
                style: tt.titleMedium?.copyWith(color: scheme.primary),
              ),
              const SizedBox(height: 12),
              for (final c in clocks) _tile(context, c, places),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(BuildContext context, Rec c, List<Rec> places) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final on = c['on'] == true;
    final atPlace = c['place'] != null;
    final place = Clock.place(places, c['place']);
    final label = (c['label'] as String?)?.isNotEmpty == true ? c['label'] as String : null;
    final lines = [
      if (atPlace)
        '${c['when'] == 'leave' ? 'When I leave' : 'When I arrive at'} ${place?['name'] ?? 'a deleted place'}'
            '${c['once'] == false ? ', every time' : ''}'
      else
        Clock.daysText(Clock.days(c)),
      if (label != null) label,
      if (c['soundName'] != null) '♪ ${c['soundName']}',
    ];
    final faded = on ? null : scheme.onSurfaceVariant;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showAlarmEditor(context, store, clock: c, atPlace: atPlace),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (atPlace)
                  Row(children: [
                    Icon(Icons.place, color: on ? scheme.primary : faded),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(place?['name'] as String? ?? 'Place', style: tt.headlineSmall?.copyWith(color: faded)),
                    ),
                  ])
                else
                  Text(c['time'] as String, style: tt.displaySmall?.copyWith(color: faded)),
                const SizedBox(height: 4),
                Text(lines.join(' · '), style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
            Switch(
              value: on,
              onChanged: (v) async {
                Haptics.toggle(v);
                if (v && atPlace && !await ensureLocation(context)) return;
                c['on'] = v;
                c['at'] = null;
                store.save();
                await Clock.sync(store);
                if (v && !atPlace && context.mounted) _told(context, c);
              },
            ),
          ]),
        ),
      ),
    );
  }
}

void _told(BuildContext context, Rec c) {
  final t = Clock.next(c['time'] as String, Clock.days(c), DateTime.now());
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Alarm set for ${Clock.until(t, DateTime.now())}')));
}

/// Adds or edits an alarm. [atPlace] makes a place alarm instead of a time alarm.
Future<void> showAlarmEditor(BuildContext context, Store s, {Rec? clock, bool atPlace = false}) {
  final label = TextEditingController(text: clock?['label'] as String? ?? '');
  var time = clock?['time'] as String? ?? '07:00';
  final days = <int>{...Clock.days(clock ?? {})};
  int? placeId = clock?['place'] as int?;
  var when = clock?['when'] as String? ?? 'arrive';
  var once = clock?['once'] != false;
  String? sound = clock?['sound'] as String?;
  String? soundName = clock?['soundName'] as String?;
  String? note;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final tt = Theme.of(ctx).textTheme;
      final scheme = Theme.of(ctx).colorScheme;
      final place = Clock.place(s.list('places'), placeId);

      Future<void> pickTime() async {
        final p = time.split(':');
        final t = await showTimePicker(
          context: ctx,
          initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])),
        );
        if (t != null) setS(() => time = '${two(t.hour)}:${two(t.minute)}');
      }

      Future<void> pickMusic() async {
        if (kIsWeb) return;
        final r = await FilePicker.platform.pickFiles(type: FileType.audio);
        final f = r?.files.single;
        if (f?.path == null) return;
        // A copy in the app's own folder, so the alarm still rings if the original is moved.
        final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/alarm_sounds');
        await dir.create(recursive: true);
        final copy = await File(f!.path!).copy('${dir.path}/${DateTime.now().millisecondsSinceEpoch}_${f.name}');
        Haptics.success();
        setS(() {
          sound = copy.path;
          soundName = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
        });
      }

      Future<void> save() async {
        if (atPlace && placeId == null) {
          Haptics.reject();
          return setS(() => note = 'Choose a place first.');
        }
        final fields = <String, dynamic>{
          'label': label.text.trim(),
          'on': true,
          'sound': sound,
          'soundName': soundName,
          'at': null,
          if (atPlace) ...{'place': placeId, 'when': when, 'once': once} else ...{'time': time, 'days': days.toList()..sort()},
        };
        Rec c;
        if (clock == null) {
          c = {'id': s.nextId(), ...fields};
          s.list('clocks').add(c);
        } else {
          c = clock..addAll(fields);
        }
        s.save();
        Haptics.success();
        if (ctx.mounted) Navigator.pop(ctx);
        if (atPlace) {
          final ok = context.mounted && await ensureLocation(context);
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Saved. It needs location "Allow all the time" to ring at the place.'),
            ));
          }
        }
        await Clock.sync(s);
        if (!atPlace && context.mounted) _told(context, c);
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (!atPlace) ...[
              Center(
                child: TextButton(
                  onPressed: pickTime,
                  child: Text(time, style: tt.displayMedium?.copyWith(color: scheme.primary)),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(Clock.dayNames[d - 1]),
                    selected: days.contains(d),
                    onSelected: (v) {
                      Haptics.tick();
                      setS(() => v ? days.add(d) : days.remove(d));
                    },
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(days.isEmpty ? 'Rings once. Pick days to repeat it.' : 'Repeats: ${Clock.daysText(days.toList())}',
                    style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            ] else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined),
                title: Text(place?['name'] as String? ?? 'Choose a place'),
                subtitle: place == null ? null : Text('Within ${place['radius'] ?? 200} m'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final id = await pickPlace(ctx, s, current: placeId);
                  if (id != null) setS(() => placeId = id);
                },
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'arrive', label: Text('When I arrive'), icon: Icon(Icons.login)),
                  ButtonSegment(value: 'leave', label: Text('When I leave'), icon: Icon(Icons.logout)),
                ],
                selected: {when},
                onSelectionChanged: (v) {
                  Haptics.segment();
                  setS(() => when = v.first);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Every time'),
                subtitle: const Text('Off: rings once, then switches itself off'),
                value: !once,
                onChanged: (v) {
                  Haptics.toggle(v);
                  setS(() => once = !v);
                },
              ),
            ],
            TextField(
              controller: label,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Label (optional)', hintText: 'Wake up, Get off the bus'),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.music_note_outlined),
              title: Text(soundName ?? "Phone's alarm sound"),
              subtitle: const Text('Plays on repeat until you stop it'),
              trailing: Wrap(children: [
                if (sound != null)
                  IconButton(
                    tooltip: "Use the phone's alarm sound",
                    icon: const Icon(Icons.close),
                    onPressed: () => setS(() {
                      sound = null;
                      soundName = null;
                    }),
                  ),
                TextButton(onPressed: kIsWeb ? null : pickMusic, child: const Text('Choose music')),
              ]),
            ),
            if (note != null) Text(note!, style: TextStyle(color: scheme.error)),
            const SizedBox(height: 8),
            Row(children: [
              if (clock != null)
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  onPressed: () async {
                    Haptics.warn();
                    s.list('clocks').removeWhere((x) => x['id'] == clock['id']);
                    s.save();
                    await Native.cancel(clock['id'] as int);
                    if (ctx.mounted) Navigator.pop(ctx);
                    await Clock.sync(s);
                  },
                ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => Native.ringNow(label.text.trim().isEmpty ? 'Test alarm' : label.text.trim(), sound),
                child: const Text('Test'),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: save, child: Text(clock == null ? 'Add' : 'Save')),
            ]),
          ]),
        ),
      );
    }),
  );
}
