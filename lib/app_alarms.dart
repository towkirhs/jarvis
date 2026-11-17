import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'clock.dart';
import 'day_log.dart';
import 'haptics.dart';
import 'native.dart';
import 'store.dart';

/// An app alarm on the Clock's list: what it watches, and its switch.
class AppAlarmTile extends StatelessWidget {
  const AppAlarmTile({super.key, required this.store, required this.alarm});
  final Store store;
  final Rec alarm;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final on = alarm['on'] != false;
    final faded = on ? null : scheme.onSurfaceVariant;
    final text = (alarm['text'] as String?)?.trim() ?? '';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showAppAlarmEditor(context, store, alarm: alarm),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.apps, color: on ? scheme.primary : faded),
                  const SizedBox(width: 8),
                  Flexible(child: Text(AppAlarm.describe(alarm), style: tt.titleMedium?.copyWith(color: faded))),
                ]),
                const SizedBox(height: 4),
                Text(
                  [alarm['ring'] == true ? 'Rings an alarm' : 'Notification', if (text.isNotEmpty) text].join(' · '),
                  style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ]),
            ),
            Switch(
              value: on,
              onChanged: (v) async {
                Haptics.toggle(v);
                await store.updateRec('appAlarms', alarm, '${v ? 'Turned on' : 'Turned off'}: ${AppAlarm.describe(alarm)}', (x) => x['on'] = v);
                await Clock.sync(store);
              },
            ),
          ]),
        ),
      ),
    );
  }
}

/// Adds or edits an app alarm: which app, when (on opening it, over a time today, or in one go), and how.
Future<void> showAppAlarmEditor(BuildContext context, Store s, {Rec? alarm}) {
  String? pkg = alarm?['pkg'] as String?;
  String? name = alarm?['name'] as String?;
  var when = alarm?['when'] as String? ?? 'open';
  var ring = alarm?['ring'] == true;
  final minutes = TextEditingController(text: '${alarm?['min'] ?? 60}');
  final text = TextEditingController(text: alarm?['text'] as String? ?? '');
  String? note;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final tt = Theme.of(ctx).textTheme;
      final scheme = Theme.of(ctx).colorScheme;

      Future<void> pickApp() async {
        final picked = await showAppPicker(ctx);
        if (picked != null) setS(() => (pkg, name) = (picked.pkg, picked.name));
      }

      Future<void> save() async {
        final min = int.tryParse(minutes.text.trim());
        if (pkg == null) return setS(() => note = 'Choose an app first.');
        if (when != 'open' && (min == null || min < 1 || min > 1440)) return setS(() => note = 'Minutes: a number from 1 to 1440.');
        final fields = <String, dynamic>{
          'pkg': pkg, 'name': name, 'when': when, 'min': min ?? 60, 'ring': ring, 'text': text.text.trim(), 'on': true,
        };
        if (alarm == null) {
          final a = {'id': s.nextId(), ...fields};
          s.list('appAlarms').add(a);
          s.logAction('App alarm: ${AppAlarm.describe(a)}', [
            {'op': 'rm', 'col': 'appAlarms', 'id': a['id']},
          ]);
          s.save();
        } else {
          await s.updateRec('appAlarms', alarm, 'Changed app alarm: ${AppAlarm.describe({...alarm, ...fields})}', (x) => x.addAll(fields));
        }
        Haptics.success();
        if (ctx.mounted) Navigator.pop(ctx);
        await Clock.sync(s);
        if (context.mounted && !await Native.usageAccess()) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            persist: false,
            content: const Text('Saved. It needs Usage access to know which app is open.'),
            action: SnackBarAction(label: 'Allow', onPressed: Native.openUsageAccess),
          ));
        }
      }

      ChoiceChip choice(String label, bool selected, VoidCallback onTap) => ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) {
              Haptics.segment();
              onTap();
            },
          );

      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(alarm == null ? 'App alarm' : 'Change app alarm', style: tt.headlineSmall),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              color: scheme.surfaceContainerHighest,
              child: ListTile(
                leading: const Icon(Icons.apps),
                title: Text(name ?? 'Choose an app'),
                trailing: const Icon(Icons.chevron_right),
                onTap: kIsWeb ? null : pickApp,
              ),
            ),
            const SizedBox(height: 16),
            Text('When', style: tt.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              choice('When I open it', when == 'open', () => setS(() => when = 'open')),
              choice('Over a time today', when == 'today', () => setS(() => when = 'today')),
              choice('Too long in one go', when == 'sitting', () => setS(() => when = 'sitting')),
            ]),
            if (when != 'open') ...[
              const SizedBox(height: 12),
              TextField(
                controller: minutes,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Minutes',
                  helperText: when == 'today' ? 'Added up since midnight; once a day' : 'Without leaving the app',
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text('How', style: tt.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              choice('Notification', !ring, () => setS(() => ring = false)),
              choice('Alarm on the full screen', ring, () => setS(() => ring = true)),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: text,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Message (optional)', hintText: 'Enough YouTube, back to study'),
            ),
            if (note != null) ...[
              const SizedBox(height: 8),
              Text(note!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 16),
            Row(children: [
              if (alarm != null)
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  onPressed: () async {
                    Haptics.warn();
                    s.removeRec('appAlarms', alarm, 'Deleted app alarm: ${AppAlarm.describe(alarm)}');
                    if (ctx.mounted) Navigator.pop(ctx);
                    await Clock.sync(s);
                  },
                ),
              const Spacer(),
              FilledButton(onPressed: save, child: Text(alarm == null ? 'Add' : 'Save')),
            ]),
          ]),
        ),
      );
    }),
  );
}

/// A searchable list of the phone's apps.
Future<({String pkg, String name})?> showAppPicker(BuildContext context) {
  final apps = Native.apps();
  var query = '';
  return showModalBottomSheet<({String pkg, String name})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.8,
      child: StatefulBuilder(builder: (ctx, setS) {
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search apps'),
              onChanged: (v) => setS(() => query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map>>(
              future: apps,
              builder: (ctx, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final shown = snap.data!.where((a) => '${a['name']}'.toLowerCase().contains(query)).toList();
                if (shown.isEmpty) return const Center(child: Text('No app with that name'));
                return ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (ctx, i) => ListTile(
                    title: Text('${shown[i]['name']}'),
                    onTap: () => Navigator.pop(ctx, (pkg: '${shown[i]['pkg']}', name: '${shown[i]['name']}')),
                  ),
                );
              },
            ),
          ),
        ]);
      }),
    ),
  );
}
