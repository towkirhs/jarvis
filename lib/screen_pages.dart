import 'package:flutter/material.dart';

import 'about_me_page.dart';
import 'arrange.dart';
import 'clock_screen.dart';
import 'countdown_screen.dart';
import 'data_page.dart';
import 'day_page.dart';
import 'drive_page.dart';
import 'habits_screen.dart';
import 'health_page.dart';
import 'ics_page.dart';
import 'items_screen.dart';
import 'journal_screen.dart' show JournalScreen;
import 'memory_page.dart';
import 'money.dart';
import 'pages.dart';
import 'phone_calendar_page.dart';
import 'plan_day_page.dart';
import 'recall_page.dart';
import 'rules_page.dart';
import 'store.dart';
import 'voice_page.dart';

/// The page for screen [key] (see [Arrange.all]), as a bottom tab or opened from More.
Widget pageFor(String key, Store s) => switch (key) {
      'plan' => ItemsScreen(store: s),
      'money' => MoneyPage(store: s),
      'journal' => JournalScreen(store: s),
      'habits' => HabitsScreen(store: s),
      'planDay' => PlanDayPage(store: s),
      'day' => DayPage(store: s),
      'clock' => ClockScreen(store: s),
      'inbox' => InboxPage(store: s),
      'promises' => PromisesPage(store: s),
      'countdowns' => CountdownPage(store: s),
      'cards' => RecallPage(store: s),
      'insights' => InsightsPage(store: s),
      'decisions' => DecisionsPage(store: s),
      'memory' => MemoryPage(store: s),
      'aboutMe' => AboutMePage(store: s),
      'rules' => RulesPage(store: s),
      'voice' => VoicePage(store: s),
      'drive' => DrivePage(store: s),
      'phoneCal' => PhoneCalendarPage(store: s),
      'ics' => IcsPage(store: s),
      'health' => HealthPage(store: s),
      'data' => DataPage(store: s),
      'activity' => ActivityPage(store: s),
      'arrange' => ArrangePage(store: s),
      'settings' => SettingsPage(store: s),
      'more' => MoreScreen(store: s),
      _ => const SizedBox.shrink(),
    };

/// A short live note under a tile in More, where one helps (what is waiting, what is running).
String? screenNote(String key, Store s) => switch (key) {
      'inbox' => s.list('inbox').isEmpty ? null : '${s.list('inbox').length} waiting',
      'promises' => switch (s.list('promises').where((p) => p['status'] == 'open').length) { 0 => null, final n => '$n open' },
      'cards' => switch (dueCards(s)) { 0 => null, final n => '$n due' },
      'clock' => s.focusActive == null ? null : 'Focus on',
      _ => null,
    };
