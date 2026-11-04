import 'dart:async';

import 'package:flutter/material.dart';

import 'brain.dart';
import 'focus_screen.dart';
import 'habits_screen.dart';
import 'home_screen.dart';
import 'items_screen.dart';
import 'journal_screen.dart';
import 'native.dart';
import 'pages.dart';
import 'store.dart';

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
      for (final note in notes) {
        await Brain.capture(store, note, source: 'handy');
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
  Widget build(BuildContext context) => MaterialApp(
        title: 'Jarvis',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: Shell(store: store),
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
  Timer? _timer;
  String? _summaryTried;

  Store get s => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Native.onShared = _onShared;
    Native.onNotesWaiting = _tick;
    _boot();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
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
    await _tick();
  }

  Future<void> _onShared(String text) async {
    if (mounted) setState(() => _tab = 0);
    await Brain.capture(s, text, source: 'share');
  }

  /// Runs every minute while the app is open: retries waiting notes and writes the evening summary.
  Future<void> _tick() async {
    for (final note in await Native.takeNotes()) {
      await Brain.capture(s, note, source: 'handy');
    }
    await Brain.drain(s);
    final now = DateTime.now();
    final today = dayKey(now);
    if (now.hour >= 21 &&
        s.apiKey.isNotEmpty &&
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

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _tab,
            children: [
              HomeScreen(store: s),
              ItemsScreen(store: s),
              FocusScreen(store: s),
              JournalScreen(store: s),
              HabitsScreen(store: s),
              MoreScreen(store: s),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.checklist), label: 'Plan'),
            NavigationDestination(icon: Icon(Icons.timer_outlined), selectedIcon: Icon(Icons.timer), label: 'Focus'),
            NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Journal'),
            NavigationDestination(icon: Icon(Icons.local_fire_department_outlined), selectedIcon: Icon(Icons.local_fire_department), label: 'Habits'),
            NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
          ],
        ),
      );
}
