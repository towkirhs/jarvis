import 'package:flutter/material.dart';

import 'haptics.dart';
import 'store.dart';

/// The ⋮ menu on Habits, Money, Journal and Your day: "Day starts at 5 am", the same switch everywhere
/// (Settings, the calendar's view sheet and Plan my day have it too).
class DayStartMenu extends StatelessWidget {
  const DayStartMenu({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Options',
        onSelected: (_) {
          Haptics.toggle(store.dayShift == 0);
          store.setDayShift(store.dayShift == 0);
        },
        itemBuilder: (_) => [
          CheckedPopupMenuItem(value: 'dayStart', checked: store.dayShift > 0, child: const Text('Day starts at 5 am')),
        ],
      );
}

/// The Settings switch, with what it changes.
class DayStartSwitch extends StatelessWidget {
  const DayStartSwitch({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) => SwitchListTile(
          secondary: const Icon(Icons.wb_twilight),
          title: const Text('Day starts at 5 am'),
          subtitle: const Text('Until 5 am it is still yesterday: calendar, plans, habits, money, journal and rules. '
              'Times stay as they are. On this phone.'),
          value: store.dayShift > 0,
          onChanged: (v) {
            Haptics.toggle(v);
            store.setDayShift(v);
          },
        ),
      );
}

String _ampm(int m) {
  final h = (m ~/ 60) % 24;
  final mm = m % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12${mm == 0 ? '' : ':${mm.toString().padLeft(2, '0')}'} ${h < 12 ? 'am' : 'pm'}';
}

/// "Planning 5 am – 3 am (after midnight)": the hours Plan my day fills.
String myDayLabel(Store s) => 'Planning ${_ampm(s.wakeMin)} – ${_ampm(s.sleepMin)}${s.sleepMin > 1440 ? ' (after midnight)' : ''}';

/// Your waking hours: Plan my day fills them; a bedtime after midnight stays part of the same day.
Future<void> showMyDaySheet(BuildContext context, Store s) async {
  var wake = s.wakeMin;
  var sleep = s.sleepMin % 1440;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final tt = Theme.of(ctx).textTheme;
      final late = sleep < wake;
      Future<void> pick(bool isWake) async {
        final m = isWake ? wake : sleep;
        final t = await showTimePicker(context: ctx, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
        if (t != null) setS(() => isWake ? wake = t.hour * 60 + t.minute : sleep = t.hour * 60 + t.minute);
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('My day', style: tt.headlineSmall),
          const SizedBox(height: 4),
          Text('Plan my day fills the time between these. Sleeping after midnight keeps the night part of the same day.',
              style: tt.bodyMedium?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.wb_sunny_outlined),
            title: const Text('I wake up'),
            trailing: Text(_ampm(wake), style: tt.titleMedium),
            onTap: () => pick(true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bedtime_outlined),
            title: const Text('I go to sleep'),
            subtitle: late ? Text(sleep >= 300 ? 'Too late: the day ends at 5 am, so 4:59 am' : 'After midnight, still the same day') : null,
            trailing: Text(_ampm(late && sleep >= 300 ? 299 : sleep), style: tt.titleMedium),
            onTap: () => pick(false),
          ),
          if (late && s.dayShift == 0)
            Text('This turns on "Day starts at 5 am".', style: tt.bodySmall),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () async {
                await s.setMyDay(wake: wake, sleep: sleep);
                Haptics.success();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ),
        ]),
      );
    }),
  );
}

/// Settings: the waking hours, under "Day starts at 5 am".
class MyDayTile extends StatelessWidget {
  const MyDayTile({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListTile(
          leading: const Icon(Icons.bedtime_outlined),
          title: const Text('When I wake and sleep'),
          subtitle: Text(myDayLabel(store)),
          onTap: () => showMyDaySheet(context, store),
        ),
      );
}
