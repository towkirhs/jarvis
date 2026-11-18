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
