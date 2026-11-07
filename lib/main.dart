import 'dart:async';

import 'package:flutter/material.dart';

import 'ai.dart';
import 'haptics.dart';
import 'brain.dart';
import 'capture_page.dart';
import 'money.dart';
import 'habits_screen.dart';
import 'home_screen.dart';
import 'items_screen.dart';
import 'journal_screen.dart';
import 'native.dart';
import 'pages.dart';
import 'store.dart';
import 'sync.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store();
  await store.load();
  Native.init();
  runApp(JarcisApp(store: store));
}

/// Started by Android when Handy sends a note while the app is closed: process it, then exit.
@pragma('vm:entry-point')
Future<void> backgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final store = Store();
    await store.load();
    while (true) {
      final notes = await Native.takeNotes();
      if (notes.isEmpty) break;
      for (final (text, image, source) in notes) {
        await Brain.capture(store, text.isEmpty ? '(shared image)' : text, source: source, image: image);
      }
    }
    // save() doesn't wait for the disk write; give it a moment before the engine is destroyed.
    await Future<void>.delayed(const Duration(milliseconds: 500));
  } finally {
    await Native.backgroundDone();
  }
}

class JarcisApp extends StatelessWidget {
  const JarcisApp({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final pick = (store.settings['theme'] as String?) ?? 'system';
          final accent = (store.settings['accent'] as String?) ?? 'default';
          Haptics.on = store.settings['haptics'] != false;
          return MaterialApp(
            title: 'Jarvis',
            theme: themeFor(pick == 'latte' ? 'latte' : 'light', accent),
            darkTheme: themeFor('dark', accent),
            themeMode: switch (pick) {
              'light' || 'latte' => ThemeMode.light,
              'dark' => ThemeMode.dark,
              _ => ThemeMode.system,
            },
            home: Shell(store: store),
          );
        },
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.store});
  final Store store;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _tab = 0;
  final _pages = PageController();
  Timer? _timer;
  String? _summaryTried;

  Store get s => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Native.onShared = _onShared;
    Native.onNotesWaiting = _tick;
    Native.onDoneWaiting = _tick;
    Native.onMoneyWaiting = _tick;
    Native.onLaunchAction = _openCapture;
    _boot();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tick();
  }

  Future<void> _boot() async {
    await Native.requestNotificationPermission();
    await s.ensureDaily();
    final shared = await Native.takeSharedText();
    if (shared != null) await _onShared(shared);
    final launch = await Native.takeLaunchAction();
    if (launch != null) _openCapture(launch);
    await _tick();
  }

  /// Opened from Handy's Jarvis bubble: 'text' or 'photo'.
  void _openCapture(String action) {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CapturePage(store: s, startWithPhoto: action == 'photo')),
    );
  }

  /// Applies Done taps from notifications: finishes the item, logs the habit, or keeps the promise.
  Future<void> _applyDone() async {
    final today = dayKey(DateTime.now());
    for (final nid in await Native.takeDone()) {
      for (final it in s.list('items').where((i) => i['nid'] == nid && i['status'] == 'open').toList()) {
        await s.markDone(it);
      }
      for (final h in s.list('habits').where((h) => h['rid'] == nid).toList()) {
        await s.logHabit(h, today, 'yes');
      }
      for (final p in s.list('promises').where((p) => p['nid'] == nid && p['status'] == 'open').toList()) {
        await s.updateRec('promises', p, 'Kept promise to ${p['person']}', (r) => r['status'] = 'done');
      }
    }
  }

  Future<void> _onShared(String text) async {
    if (mounted) _goTo(0);
    await Brain.capture(s, text, source: 'share');
  }

  /// Runs every minute while the app is open: retries waiting notes and writes the evening summary.
  Future<void> _tick() async {
    await _applyDone();
    await drainMoneyQueue(s);
    for (final (text, image, source) in await Native.takeNotes()) {
      await Brain.capture(s, text.isEmpty ? '(shared image)' : text, source: source, image: image);
    }
    await Brain.drain(s);
    try {
      await Sync.run(s);
    } catch (_) {
      // Offline or GitHub is down: the next tick tries again.
    }
    final now = DateTime.now();
    final today = dayKey(now);
    if (now.hour >= 21 &&
        AI.available(s) &&
        s.summaries[today] == null &&
        _summaryTried != today &&
        s.capturesOn(today).isNotEmpty) {
      _summaryTried = today;
      try {
        await Brain.summarize(s, today);
      } catch (_) {
        // The Journal tab has a button to try again.
      }
    }
  }

  void _goTo(int i) {
    if (_pages.hasClients) {
      _pages.jumpToPage(i); // onPageChanged updates the tab
    } else {
      setState(() => _tab = i);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          // Swipe left or right anywhere to move between the main tabs.
          child: PageView(
            controller: _pages,
            onPageChanged: (i) {
              if (i != _tab) Haptics.tick();
              setState(() => _tab = i);
            },
            children: [
              for (final page in [
                HomeScreen(store: s),
                ItemsScreen(store: s),
                MoneyPage(store: s),
                JournalScreen(store: s),
                HabitsScreen(store: s),
                MoreScreen(store: s),
              ])
                _KeepAlive(child: page),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _goTo,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.checklist), label: 'Plan'),
            NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Money'),
            NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Journal'),
            NavigationDestination(icon: Icon(Icons.local_fire_department_outlined), selectedIcon: Icon(Icons.local_fire_department), label: 'Habits'),
            NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
          ],
        ),
      );
}

/// Keeps a tab's scroll position and state while you are on another tab.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
