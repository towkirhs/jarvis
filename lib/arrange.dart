import 'package:flutter/material.dart';

import 'haptics.dart';
import 'store.dart';

/// One screen of the app: it can be a bottom tab, or a tile in More.
class Screen {
  const Screen(this.key, this.name, this.icon, {this.short});
  final String key;
  final String name;
  final IconData icon;

  /// A shorter name for the bottom bar.
  final String? short;
  String get tabName => short ?? name;
}

/// How the app is arranged on this phone: the bottom tabs, the order of Home's parts, and More's tiles.
class Arrange {
  /// Every screen, in More's first order. Home and More themselves are not in it: they are always there.
  static const all = [
    Screen('plan', 'Plan', Icons.checklist),
    Screen('money', 'Money', Icons.account_balance_wallet_outlined),
    Screen('journal', 'Journal', Icons.menu_book_outlined),
    Screen('habits', 'Habits', Icons.local_fire_department_outlined),
    Screen('planDay', 'Plan my day', Icons.auto_awesome_motion, short: 'Plan day'),
    Screen('day', 'Your day', Icons.timeline, short: 'Day'),
    Screen('clock', 'Clock', Icons.alarm),
    Screen('inbox', 'Review inbox', Icons.inbox_outlined, short: 'Inbox'),
    Screen('promises', 'Promises', Icons.handshake_outlined),
    Screen('countdowns', 'Countdowns', Icons.hourglass_bottom, short: 'Dates'),
    Screen('cards', 'Flashcards', Icons.style_outlined, short: 'Cards'),
    Screen('media', 'Movies and books', Icons.movie_outlined, short: 'Watch'),
    Screen('insights', 'Insights', Icons.insights),
    Screen('decisions', 'Decisions', Icons.history_edu_outlined),
    Screen('memory', 'Memory', Icons.psychology_outlined),
    Screen('aboutMe', 'About me', Icons.record_voice_over),
    Screen('rules', 'Rules and links', Icons.account_tree_outlined, short: 'Rules'),
    Screen('voice', 'Hey Jarvis', Icons.record_voice_over_outlined, short: 'Voice'),
    Screen('drive', 'Google Drive', Icons.add_to_drive, short: 'Drive'),
    Screen('phoneCal', 'Phone calendar', Icons.event_repeat_outlined, short: 'Phone cal'),
    Screen('ics', 'Calendar file', Icons.event_note_outlined, short: 'ICS'),
    Screen('health', 'Health check', Icons.health_and_safety_outlined, short: 'Health'),
    Screen('data', 'Move data', Icons.swap_horiz, short: 'Data'),
    Screen('activity', 'Activity and undo', Icons.undo, short: 'Activity'),
    Screen('bugs', 'Bugs', Icons.bug_report_outlined),
    Screen('arrange', 'Arrange', Icons.dashboard_customize_outlined),
    Screen('settings', 'Settings', Icons.settings_outlined),
  ];

  static Screen? of(String key) => all.where((x) => x.key == key).firstOrNull;

  /// The tabs between Home and More when nothing is saved.
  static const middle = ['plan', 'money', 'journal', 'habits'];

  /// The most tabs between Home and More, so the bar stays readable.
  static const maxTabs = 5;

  /// Always in More, so you can never lock yourself out of arranging or settings.
  static const keep = {'arrange', 'settings'};

  /// The tabs to show, in order, from the saved setting ("money,plan,day"); unknown or repeated names are skipped.
  static List<String> tabs(String? saved) {
    if (saved == null) return [...middle];
    return [for (final k in saved.split(',')) if (of(k) != null) k].toSet().take(maxTabs).toList();
  }

  /// Parts of Home: the day strip, the "Do now" card and the small chips under it.
  static const homeParts = {'ribbon': 'Day strip', 'now': '"Do now" card', 'chips': 'Small chips (money today, inbox…)'};

  static Set<String> hidden(String? saved) => {for (final k in (saved ?? '').split(',')) if (homeParts.containsKey(k)) k};

  /// Home's parts in your order (anything not in [saved] keeps its place at the end).
  static List<String> homeOrder(String? saved) => _ordered(saved, homeParts.keys.toList());

  /// More's tiles in your order: every screen that is not a bottom tab.
  static List<String> moreOrder(String? saved, List<String> tabs) =>
      _ordered(saved, [for (final x in all) x.key]).where((k) => !tabs.contains(k)).toList();

  /// Tiles you hid from More (Arrange and Settings never hide).
  static Set<String> moreHidden(String? saved) =>
      {for (final k in (saved ?? '').split(',')) if (of(k) != null && !keep.contains(k)) k};

  static List<String> _ordered(String? saved, List<String> known) {
    final mine = [for (final k in (saved ?? '').split(',')) if (known.contains(k)) k].toSet().toList();
    return [...mine, ...known.where((k) => !mine.contains(k))];
  }
}

/// More → Arrange: any screen as a bottom tab, Home's parts in any order, and More's tiles ordered or hidden.
class ArrangePage extends StatefulWidget {
  const ArrangePage({super.key, required this.store});
  final Store store;

  @override
  State<ArrangePage> createState() => _ArrangePageState();
}

class _ArrangePageState extends State<ArrangePage> {
  Store get s => widget.store;
  late List<String> tabs = Arrange.tabs(s.local('tabs'));
  late List<String> home = Arrange.homeOrder(s.local('homeOrder'));
  late Set<String> homeHidden = Arrange.hidden(s.local('homeHide'));
  late List<String> more = Arrange.moreOrder(s.local('moreOrder'), tabs);
  late Set<String> moreHidden = Arrange.moreHidden(s.local('moreHide'));

  Future<void> _saveTabs() async {
    await s.setArrange(tabs: tabs.join(','));
    setState(() => more = Arrange.moreOrder(s.local('moreOrder'), tabs));
  }

  Future<void> _saveMore() => s.setArrange(moreOrder: more.join(','), moreHide: moreHidden.join(','));

  void Function(int, int) _reorder(List<String> list, Future<void> Function() save) => (from, to) {
        Haptics.tick();
        setState(() {
          final k = list.removeAt(from);
          list.insert(to > from ? to - 1 : to, k);
        });
        save();
      };

  Future<void> _addTab() async {
    final scheme = Theme.of(context).colorScheme;
    final key = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, scroll) => ListView(controller: scroll, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Add a tab', style: Theme.of(ctx).textTheme.titleLarge),
          ),
          for (final x in Arrange.all)
            if (!tabs.contains(x.key))
              ListTile(
                leading: Icon(x.icon, color: scheme.primary),
                title: Text(x.name),
                onTap: () => Navigator.pop(ctx, x.key),
              ),
        ]),
      ),
    );
    if (key == null) return;
    Haptics.success();
    setState(() => tabs.add(key));
    await _saveTabs();
  }

  Future<void> _reset() async {
    Haptics.warn();
    await s.setArrange(tabs: Arrange.middle.join(','), homeOrder: '', homeHide: '', moreOrder: '', moreHide: '');
    setState(() {
      tabs = [...Arrange.middle];
      home = Arrange.homeOrder(null);
      homeHidden = {};
      more = Arrange.moreOrder(null, tabs);
      moreHidden = {};
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget fixed(IconData icon, String name, String why) => ListTile(
          leading: const SizedBox(width: 24),
          title: Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(name)]),
          subtitle: Padding(padding: const EdgeInsets.only(left: 32), child: Text(why)),
          trailing: Icon(Icons.lock_outline, color: scheme.onSurfaceVariant),
        );
    Widget heading(String title, String help) => Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: tt.titleMedium),
            const SizedBox(height: 2),
            Text(help, style: TextStyle(color: scheme.onSurfaceVariant)),
          ]),
        );
    Widget list(List<String> keys, Future<void> Function() save, Widget Function(int i, String k) row) => ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorder: _reorder(keys, save),
          children: [for (final (i, k) in keys.indexed) row(i, k)],
        );
    Widget handle(int i) => ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle));

    return Scaffold(
      appBar: AppBar(title: const Text('Arrange')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          heading('Bottom tabs', 'Any screen can be a tab, up to ${Arrange.maxTabs}. Drag to change the order.'),
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: [
              fixed(Icons.home_outlined, 'Home', 'Always first'),
              list(tabs, _saveTabs, (i, k) {
                final x = Arrange.of(k)!;
                return ListTile(
                  key: ValueKey('tab$k'),
                  leading: handle(i),
                  title: Row(children: [Icon(x.icon, size: 20), const SizedBox(width: 12), Flexible(child: Text(x.name))]),
                  trailing: IconButton(
                    tooltip: 'Remove the tab',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () {
                      Haptics.tap();
                      setState(() => tabs.remove(k));
                      _saveTabs();
                    },
                  ),
                );
              }),
              if (tabs.length < Arrange.maxTabs)
                ListTile(
                  leading: const SizedBox(width: 24),
                  title: Row(children: [Icon(Icons.add, size: 20, color: scheme.primary), const SizedBox(width: 12), Text('Add a tab', style: TextStyle(color: scheme.primary))]),
                  onTap: _addTab,
                ),
              fixed(Icons.more_horiz, 'More', 'Always last: every screen is reachable from here'),
            ]),
          ),
          heading('Home', 'Drag to change the order; switch a part off to hide it.'),
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: [
              list(home, () => s.setArrange(homeOrder: home.join(',')), (i, k) => ListTile(
                    key: ValueKey('home$k'),
                    leading: handle(i),
                    title: Text(Arrange.homeParts[k]!),
                    trailing: Switch(
                      value: !homeHidden.contains(k),
                      onChanged: (v) {
                        Haptics.toggle(v);
                        setState(() => v ? homeHidden.remove(k) : homeHidden.add(k));
                        s.setArrange(homeHide: homeHidden.join(','));
                      },
                    ),
                  )),
              fixed(Icons.chat_bubble_outline, 'The chat', 'Always shown: it is how you tell Jarvis things'),
            ]),
          ),
          heading('More', 'Drag to change the order; switch a tile off to tuck it under "Hidden" in More.'),
          Card(
            margin: EdgeInsets.zero,
            child: list(more, _saveMore, (i, k) {
              final x = Arrange.of(k)!;
              final locked = Arrange.keep.contains(k);
              return ListTile(
                key: ValueKey('more$k'),
                leading: handle(i),
                title: Row(children: [Icon(x.icon, size: 20), const SizedBox(width: 12), Flexible(child: Text(x.name))]),
                trailing: locked
                    ? Padding(padding: const EdgeInsets.only(right: 12), child: Icon(Icons.lock_outline, color: scheme.onSurfaceVariant))
                    : Switch(
                        value: !moreHidden.contains(k),
                        onChanged: (v) {
                          Haptics.toggle(v);
                          setState(() => v ? moreHidden.remove(k) : moreHidden.add(k));
                          _saveMore();
                        },
                      ),
              );
            }),
          ),
          const SizedBox(height: 16),
          Center(child: TextButton.icon(icon: const Icon(Icons.restart_alt), label: const Text('Back to the usual layout'), onPressed: _reset)),
        ],
      ),
    );
  }
}
