import 'package:flutter/material.dart';

import 'haptics.dart';
import 'store.dart';

/// Which tabs show between Home and More, in what order, and which parts of Home show. Kept on this phone.
class Arrange {
  /// The tabs that can move or hide; Home stays first and More last, so everything stays reachable.
  static const middle = ['plan', 'money', 'journal', 'habits'];

  /// The tabs to show, in order, from the saved setting ("money,plan,habits"); unknown names are skipped.
  static List<String> tabs(String? saved) {
    if (saved == null) return middle;
    return [for (final k in saved.split(',')) if (middle.contains(k)) k].toSet().toList();
  }

  /// Parts of Home: the day strip, the "Do now" card and the small chips under it.
  static const homeParts = {'ribbon': 'Day strip', 'now': '"Do now" card', 'chips': 'Small chips (money today, inbox…)'};

  static Set<String> hidden(String? saved) => {for (final k in (saved ?? '').split(',')) if (homeParts.containsKey(k)) k};
}

/// More → Arrange screens: reorder or hide the bottom tabs, and choose what Home shows.
class ArrangePage extends StatefulWidget {
  const ArrangePage({super.key, required this.store});
  final Store store;

  @override
  State<ArrangePage> createState() => _ArrangePageState();
}

class _ArrangePageState extends State<ArrangePage> {
  Store get s => widget.store;
  late List<String> order = [...Arrange.tabs(s.local('tabs')), ...Arrange.middle.where((k) => !Arrange.tabs(s.local('tabs')).contains(k))];
  late Set<String> shown = Arrange.tabs(s.local('tabs')).toSet();
  late Set<String> homeHidden = Arrange.hidden(s.local('homeHide'));

  static const _names = {'plan': 'Plan', 'money': 'Money', 'journal': 'Journal', 'habits': 'Habits'};
  static const _icons = {
    'plan': Icons.checklist,
    'money': Icons.account_balance_wallet_outlined,
    'journal': Icons.menu_book_outlined,
    'habits': Icons.local_fire_department_outlined,
  };

  Future<void> _saveTabs() => s.setArrange(tabs: [for (final k in order) if (shown.contains(k)) k].join(','));

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget fixed(IconData icon, String name, String why) => ListTile(
          leading: Icon(icon),
          title: Text(name),
          subtitle: Text(why),
          trailing: Icon(Icons.lock_outline, color: scheme.onSurfaceVariant),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Arrange screens')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text('Bottom tabs', style: tt.titleMedium),
          const SizedBox(height: 4),
          Text('Drag to change the order. Switch a tab off to hide it; it stays in More.',
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: [
              fixed(Icons.home_outlined, 'Home', 'Always first'),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorder: (from, to) {
                  Haptics.tick();
                  setState(() {
                    final k = order.removeAt(from);
                    order.insert(to > from ? to - 1 : to, k);
                  });
                  _saveTabs();
                },
                children: [
                  for (final (i, k) in order.indexed)
                    ListTile(
                      key: ValueKey(k),
                      leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                      title: Row(children: [
                        Icon(_icons[k], size: 20),
                        const SizedBox(width: 12),
                        Text(_names[k]!),
                      ]),
                      trailing: Switch(
                        value: shown.contains(k),
                        onChanged: (v) {
                          Haptics.toggle(v);
                          setState(() => v ? shown.add(k) : shown.remove(k));
                          _saveTabs();
                        },
                      ),
                    ),
                ],
              ),
              fixed(Icons.more_horiz, 'More', 'Always last: every page is reachable from here'),
            ]),
          ),
          const SizedBox(height: 24),
          Text('Home', style: tt.titleMedium),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: [
              for (final e in Arrange.homeParts.entries)
                SwitchListTile(
                  title: Text(e.value),
                  value: !homeHidden.contains(e.key),
                  onChanged: (v) {
                    Haptics.toggle(v);
                    setState(() => v ? homeHidden.remove(e.key) : homeHidden.add(e.key));
                    s.setArrange(homeHide: homeHidden.join(','));
                  },
                ),
              ListTile(
                title: const Text('The chat'),
                subtitle: const Text('Always shown: it is how you tell Jarvis things'),
                trailing: Icon(Icons.lock_outline, color: scheme.onSurfaceVariant),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
