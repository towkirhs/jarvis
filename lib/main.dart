import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'ai.dart';
import 'clock.dart';
import 'haptics.dart';
import 'brain.dart';
import 'capture_page.dart';
import 'money.dart';
import 'habits_screen.dart';
import 'home_screen.dart';
import 'items_screen.dart';
import 'journal_screen.dart';
import 'about_me_page.dart';
import 'main_nav.dart';
import 'native.dart';
import 'pages.dart';
import 'phone_sync.dart';
import 'store.dart';
import 'sync.dart';
import 'theme.dart';
import 'updater.dart';
import 'web_reminders.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store();
  await store.load();
  Native.init();
  AI.checkOffline(); // finds a downloaded offline model in the background
  Native.setShortcuts(jsonEncode(store.settings['shortcuts'] ?? {})); // nicknames and phrases for phone actions
  Native.setSpeech(jsonEncode(store.settings['speech'] ?? {})); // when and how Jarvis talks back
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
            // Lists stretch and settle at their ends instead of stopping dead.
            scrollBehavior: const MaterialScrollBehavior().copyWith(physics: const BouncingScrollPhysics(), overscroll: false),
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
    s.addListener(_soonSync);
    s.ruleNotice.addListener(_ruleDid);
    MainNav.step = (d) {
      if (!_pages.hasClients) return;
      _pages.animateToPage((_tab + d).clamp(0, _destinations.length - 1), duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    };
    PhoneSync.watch(s);
  }

  /// A rule just acted: say which one and what it did, with Undo.
  void _ruleDid() {
    final n = s.ruleNotice.value;
    if (n == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(n.text),
      duration: const Duration(seconds: 6),
      persist: false,
      action: SnackBarAction(label: 'Undo', onPressed: () => s.undo(n.actionId)),
    ));
  }

  /// Sends a change to your other devices a few seconds after you make it (several changes go together).
  Timer? _syncSoon;
  void _soonSync() {
    if (!s.dirty || !Sync.enabled(s)) return;
    _syncSoon?.cancel();
    _syncSoon = Timer(const Duration(seconds: 5), () => Sync.run(s).catchError((_) => null));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _syncSoon?.cancel();
    s.removeListener(_soonSync);
    s.ruleNotice.removeListener(_ruleDid);
    _pages.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Coming back (or switching to this browser tab): fetch what the other device did.
      Sync.run(s, force: true).catchError((_) => null).whenComplete(_tick);
      unawaited(PhoneSync.run(s));
    }
  }

  Future<void> _boot() async {
    await Native.requestNotificationPermission();
    unawaited(sendSpeechHints(s));
    await s.ensureDaily();
    final shared = await Native.takeSharedText();
    if (shared != null) await _onShared(shared);
    final launch = await Native.takeLaunchAction();
    if (launch != null) _openCapture(launch);
    await _tick();
    unawaited(PhoneSync.run(s));
    if (mounted) await Updater.checkDaily(context, s);
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
    s.linkHabitsNow();
    s.ruleTick();
    if (kIsWeb) WebReminders.check(s);
    await _applyDone();
    await Clock.drainFired(s);
    await Clock.drainVoiceAlarms(s);
    await Clock.sync(s);
    await drainMoneyQueue(s);
    for (final (said, did, ts) in await Native.takeCommandLog()) {
      logCommand(s, said, did, ts: ts);
    }
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

  static const _destinations = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.checklist, Icons.checklist, 'Plan'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'Money'),
    (Icons.menu_book_outlined, Icons.menu_book, 'Journal'),
    (Icons.local_fire_department_outlined, Icons.local_fire_department, 'Habits'),
    (Icons.more_horiz, Icons.more_horiz, 'More'),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 840) return _phone(context);
    // A computer screen: tabs down the side, and the page kept to a readable width.
    return Scaffold(
      body: SafeArea(
        child: Row(children: [
          NavigationRail(
            selectedIndex: _tab,
            onDestinationSelected: _goTo,
            extended: width >= 1200,
            labelType: width >= 1200 ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            destinations: [
              for (final (icon, selected, label) in _destinations)
                NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: Text(label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 960), child: _pagesView()),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _phone(BuildContext context) => Scaffold(
        body: SafeArea(child: _pagesView()),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _goTo,
          destinations: [
            for (final (icon, selected, label) in _destinations)
              NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
          ],
        ),
      );

  // Swipe left or right anywhere to move between the main tabs.
  Widget _pagesView() => PageView(
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
