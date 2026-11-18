# Jarvis

My free personal-assistant app: Flutter, Android first, plus a web build at https://towkirhs.github.io/jarvis/.
Package `com.towkirhs.jarcis`. Companion app: Handy (towkirhs/handy). See `DECISIONS.md` for past decisions.

About me: Bangladesh (Asia/Dhaka, UTC+6). Nothing phone with an Essential Key mapped to "Talk to Jarvis".
I install releases with Obtainium or in-app (More → Settings → Update). I develop on Windows 10 (a debloated build).

## Rules
- Never commit secrets. I add GitHub secrets myself; never run `gh secret set`.
- AI keys stay on the device only, never in synced state or backups. Synced data is encrypted with my passphrase.
- AI addresses must be https only.
- Coding style (Karpathy guidelines): think first and state assumptions; ask when unclear; keep it simple;
  make surgical changes that match the existing style; work toward goals you can verify (a failing test first).
- Mention unrelated dead code instead of deleting it.
- **Never uninstall the real Jarvis app from my phone**: all my data lives in it.

## Layout
- `lib/`: the Flutter app. `test/`: Dart tests.
- `android_overlay/`: the Android manifest and Kotlin files. There is no committed `android/` folder:
  CI runs `flutter create`, then copies the overlay in (`.github/workflows/build.yml`).
  **A new Kotlin file must be added to the copy list in that workflow.** Kotlin unit tests: `android_overlay/test/`.
- `docs/chatgpt-project.md`: the instructions for my ChatGPT Project and the `JARVIS v1` block format
  (read by `lib/chatgpt_block.dart`). Keep both in step if the item format in `lib/brain.dart` changes.

## Build and release
- CI (`.github/workflows/build.yml`) runs on every push: `flutter analyze`, `flutter test`, the release APK
  (arm64 only), Kotlin tests via Gradle, and the web build.
- A push to `main` publishes release `build-N` (APK `jarcis.apk`, plus `jarcis-web.zip`) and the web app.
- Workflow: work on a branch → test locally → push the branch → wait for CI → merge to main with `--ff-only` → push.
  Watch CI with `gh run watch <id> -R towkirhs/jarvis --exit-status`.
- CI pins Flutter 3.47.9 (`flutter-version` in the workflow): 3.50.0 broke the release build in Android lint.
- CI often fails with 504s downloading Gradle or Kotlin files. That isn't a code error: re-run the failed job.
- Releases are signed with a fixed key from a repo secret, so they update over each other.

## Overhaul branch
- `overhaul` is a phased revamp aimed at Google Play. Order: voice and understanding → bubble and quick capture →
  look and feel → security and store readiness. Phases 1–3 were merged to main on 2026-11-10 (my call, before
  phone testing); phase 4 (security and Play Store) is on hold until I say so.
- Every push to `overhaul` publishes a pre-release `overhaul-N` with `jarvis-dev.apk`: a separate app
  ("Jarvis Dev", `com.towkirhs.jarcis.dev`) that installs next to the real one with its own empty data.

## Design (on `overhaul`)
- All looks come from `lib/theme.dart`: `_scheme` (colours) and `polish` (shapes, type, motion). Screens take
  colours from the theme's `ColorScheme`; do not hard-code new ones.
- Kingfisher teal `#0B7285` is the default accent, with its orange as `tertiary` for the one urgent thing.
  Behind any accent the surfaces are the same neutrals: ground = `surface`, cards = `surfaceContainerLow`
  (white by day, graphite by night), fields = `surfaceContainerHighest`. `primaryContainer` is a soft accent
  wash with normal `onSurface` text.
- Shapes: 14 fields/buttons, 20 cards/FAB/menus, 28 dialogs/sheets, pill chips. Titles in Bricolage.
- Pages slide (Cupertino transition) and lists bounce. The FAB is the one solid-accent action per screen.

## Local development (Windows)
- Recreate the Android scaffold the same way CI does (the "Generate scaffold" and "Apply Android overlay" steps
  in the workflow). They are bash commands: run them in Git Bash. Re-copy the overlay after editing Kotlin files.
- Fast checks: `flutter analyze --no-fatal-infos` and `flutter test`; Kotlin: `cd android && ./gradlew :app:testDebugUnitTest`.
- **A local build cannot install over the released app** (different signing key), and uninstalling loses my data.
  Install local builds as a separate app: give the local debug build `applicationIdSuffix = ".dev"`
  (in the generated `android/` only, never in CI). Read phone logs with `adb logcat`.

## Open items
1. UI: animations ignore the reduced-motion setting. Accounts shows both an "Add account" button and an
   "Account" FAB.
2. Not yet confirmed on my phone: the build-128 Essential Key fix, the "Hey Jarvis" standby fix (build 138),
   voice briefing questions (build 140), ChatGPT blocks (build 143).
3. On `overhaul`, untested on a phone: `untilDone` items (ring daily until marked done), speech language
   setting (default en-IN), listening card retry, notes with before/until/if/every going to the AI.
   Also the typing card (`TypeActivity` in `QuickNote.kt`): Handy's bubble "text" and the action
   `com.towkirhs.jarcis.TYPE` open it over the current app, and Jarvis answers inside it.
4. Rent (`lib/rent_more.dart`), untested on a phone: All bills by month, receipts (save as image uses the
   system Save dialog; there is no native share yet, so sharing is "Copy as text"), payment methods, and
   tenant meetings (calendar events with `meeting: true`).
   Countdown reminders (`CountdownAlert` in `lib/clash.dart`: days before, time, alarm or notification) are also untested on a phone.
   Loans and debts (`lib/loans_page.dart`, collections `loanPeople` and `loans`) are untested on a phone too; no photo attachment,
   and Jarvis chat/AI does not know about them yet.
   Planning (build after 198): the engine page, 80/20 (`vital`) and GTD lists are gone (old `vital`, `gtdReview` data is ignored);
   the Eisenhower matrix stays (Plan tab, and the grid icon in Plan my day). Focus "Deep" mode and flashcards (`cards`, Leitner
   boxes, More → Flashcards) stay. Countdown groups (`group`), calendar 1-day and 30-day views. Untested on a phone.
   Money categories (`lib/categories.dart`, `lib/categories_page.dart`): one spelling per category, merge rules in `settings.catRules`
   (`expense:groceries` → `Food`), applied in `Store.addTx` and the edit sheet. Untested on a phone.
   Habits from the calendar (`lib/habit_link.dart`): a habit's `link` words match finished events and done tasks (last 14 days);
   logs written with `cal: true`, run on every save and on resume; manual logs win. The other way, `toCal: true` adds an event (`habitId`, `habitDay`, list 'Habits') when you tick the habit,
   moved or removed with the log (`Store._habitBlock`). Plan my day: quick tasks (`DayPlanner.isQuick`, item `quick`) get no block;
   habits with `planMin` (or duration target) get one, applied as a task with `planHabit` that logs the habit when done. Untested on a phone.
   Web and sync (build after 176): records carry `_t` (set in `Store.save` via `Stamps`), deletions go to `_gone`;
   `SyncMerge.merge` keeps the newer record and applies deletions; any list of id'd maps is a collection. Sync pulls every
   minute, pushes 5 s after a change, and on resume. Setup code (`Sync.makeCode`, `JARVIS-SYNC1.`) joins a device.
   Web: PWA files in `web_overlay/` (copied by CI), browser notifications (`lib/web_notify*.dart`, `WebReminders`),
   NavigationRail at ≥ 840 px. Untested on a real phone/PC pair.
   Calendar overhaul (`lib/cal_index.dart`, `cal_grid.dart`, `cal_quick.dart`, `cal_event.dart`, `cal_edit.dart`, `phone_calendar.dart`,
   `phone_sync.dart`): repeats show on every date (`CalIndex`); items gained `location`, `color`, `span` (all-day days) and `skip`
   (skipped repeat dates). Swipeable time grid with long-press drag, bottom-handle resize, tap an empty slot for quick add (the Calendar
   tab's FAB opens it too), event view sheet (Edit this date / Skip this date). Phone calendar two-way sync: More → Phone calendar (needs the calendar permission). Only timed events are
   mirrored; skipped dates are mirrored for timed repeats only; use one phone as the write-to device or events duplicate. Widget tests
   cover the grid in CI; untested on a real phone.
   Calendar views (build after 205): the "Today" button opens a sheet (`_CalendarViewState._viewSheet`): go to today, pick a
   date, span (1, 2, 3 days, week, 15, 30 days, month), "Hours across" (TimelineGrid, a row per day) or down (TimeGrid up to a week;
   15 and 30 days down are a list of days), "Overlap events" (`TimeGrid.stack`), and "Use this as my default" (`local('calView')`,
   "days|across|stack", per device). List / Calendar / Matrix swipe (`EdgeSwipe`); past the first or last tab the swipe moves the
   main tabs (`MainNav.step`); over the hour grid a swipe changes days. A day's list shows its journal; the journal's day page
   shows "On your calendar". Every SnackBar with an action has `persist: false`: Flutter now keeps those open until dismissed
   otherwise, which was the "pop-ups do not close" bug. Untested on a phone.
   "Day starts at 5 am" (build after 208): `Store.dayShift` (300 or 0, `local('dayStart5')`, per device), switched from the
   calendar's view sheet or Plan my day's menu (same setting). Only grouping and drawing change, never stored times:
   `CalIndex.build(shift:)` puts timed items before 5 am on the day before (all-day items keep their date), `CalIndex.dayOf`
   says which day a moment belongs to, the grids draw 5 am → 4:59 am (`gridMinute`), and `DayPlanner.plan(dayShift:)` treats
   5 am to 5 am as the day (late at night it may plan until 5 am). Since build 246 it applies everywhere through `DayStart`
   (`lib/day_start.dart`, pure, exported by store.dart; `minutes` set by `Store.load`/`setDayShift`): `DayStart.key(ms)` and
   `today()` replace `dayKey(fromMs(..))`/`dayKey(DateTime.now())`; `itemDay` keeps all-day items on their date; habits get
   `DayStart.now()`/`of(now)` as their day (logged times stay real); money months, journal, focus, countdowns, Your day, the
   local parser's today/tomorrow, the AI prompt and context (`Brain.dayStartNote`) follow it. Switch: Settings → Everyday,
   the ⋮ menu (`DayStartMenu`) on Habits, Money, Journal and Your day, the calendar view sheet and Plan my day. Not shifted:
   Home's hour ribbon, quick answers, loans and rent dates.
   Batch 5 (build after 213): nudge limit 1-50 or "No limit" (`settings.cap` 0 → `Store.cap` huge). Home's glance row has a Clock
   card (next alarm → ClockScreen). Chat keywords with a colon (`Destination._colon`): `decide:` (odds via `Brain.decide`,
   options from "A or B" by `Decide.options`, shown as bars in the chat from `c['decision']`), `decided: X because Y`
   (decision log, no AI), `promise:` (a promise even without a date: `asked: true` skips the deadline review). The Decide page
   is gone; More → Decisions keeps the log. Money: Stats is a dashboard (`lib/money_stats.dart` pure: month sums, savings rate,
   month-end forecast vs 3-month average, 6-month bars, category changes, net worth line, runway, spend by weekday) above the
   category donut; new Goals tab (collection `goals`: {name, target, due, account or hand `adds`, start, startSaved}, per-month
   needed, pace, on track) and long-term savings (account `savings: true`); Money's tabs swipe (`EdgeSwipe`). Untested on a phone.
   Income (build after 219): Money's tabs are Daily, Stats (chips: Overview, Calendar, Month by month), Goals, Income, Accounts.
   The Income tab (`lib/income_tab.dart`) sums rent, salaries and loans ("Each month", "People owe you", "You owe") and opens
   RentPage and LoansPage (their More tiles are gone). Income sources (`lib/income.dart` pure; `incomes` {name, kind, amount,
   start, end}, `incomePays`): a month is owed once it has ended; "Received" adds the payment and an income transaction. One
   switch turns the rent and loan money rules on or off together. Rent: dues counted up to this month or 1-2 back
   (`Rent.dueThrough`, `local('rentBack')`); bills may carry meter readings {from, to, rate} (`Rent.meter`, `lastReading`,
   unit prices in `settings.rentRates`), kinds now include water and gas; a house expense "the tenant paid" adds a rentPays
   record with method 'Maintenance' and `cost` (no rent rule event). The receipt (`_ReceiptPaper` in `rent_more.dart`) follows
   a printed rent receipt form and prints through `printing` (the paper as an image on an A4 PDF page). Untested on a phone.
   Alarm screen (build after 226): `RingService` now opens `RingActivity` directly (`startActivity`, allowed by the draw-over-apps
   permission) as well as asking for a full-screen notification, which Android honours only on a locked phone and, from Android 14,
   only when "full screen notifications" is allowed. Alarms on tasks and events (`kind: alarm`) ring through `RingService` too
   (Done marks the item done) unless `AlarmPrefs.fullAlarm` is off; reminders open a full-screen card (Done, Snooze, Close) when
   `fullNotice` is on. Back does not close the screen. `AlarmPrefs` (native prefs `jarcis_alarm`): `sound`/`soundName` = the
   ringtone for every alarm without its own. Settings → Alarms and reminders (`lib/alarm_settings_page.dart`) has the switches,
   the sound, permission fixes and test alarms. Untested on a phone.
   Alarm intensity and sounds (build after 232; `lib/alarm_sound.dart`): a style {vol 10-100, rise, vib} per Clock alarm
   (`clocks.style`, sent as JSON through `Native.clock` → scheduler entry `style` → `RingService`) or for all alarms
   (`AlarmPrefs.style`). `vol` sets the phone's alarm stream while ringing and puts it back after; `rise` fades in over ~1 min.
   Built-in sounds in `assets/sounds/` (Digital alarm 1 and 2, Universfield via Pixabay) are copied to `alarm_sounds/` when picked;
   `AlarmSounds.ensureDefault` makes Digital alarm the global sound once per phone (`local('defaultSound')`). Untested on a phone.
   Chat alarms (build after 238): an `alarm` from the chat, the local parser or ChatGPT becomes a Clock alarm (`clocks`,
   one-time `at` or daily/weekly `days`). A plain one (`Clock.plainAlarm`: "Alarm", "Wake up") is only that; otherwise it
   links (`clocks.item`, `items.clock`, `clocks.off` = ms before/after the item) to an open item with the same title or a new
   task, unless `alarmOnly`. `Store._syncLinkedClock` turns it off when the item is finished and moves it with the item; when it
   rings at the item's own time the item's notice is skipped. Deleting the item removes its alarm. Alarms in a note are applied
   last. `untilDone`, place and monthly/yearly alarms stay items.
   Health and backups (build after 249): `lib/health_page.dart` (`HealthCheck.rows` pure) reads `Native.health()` (`Health` in
   Ring.kt: notifications, exact alarms, battery optimisation, overlay, full screen, usage access) and shows fixes; it also arms the
   nightly background test (`Health.BEAT_ID` 1.7e9, kind `beat`, 3:30 am, no sound; `AlarmReceiver` records `beatAt`/`beatDue`),
   armed on boot too. `lib/backups.dart`: a daily backup file `backups/jarvis-YYYY-MM-DD.json` in app documents (last 14, made on
   the tick), "Save a backup file" (Android Save dialog), "Restore from a file" / "Daily backups" with a summary and a
   `before-restore-*.json` copy first. Settings → Everyday and More → App have Health check. Untested on a phone.
   Your day (build after 228; `lib/day_log.dart` pure, `lib/day_page.dart`, `lib/app_alarms.dart`, `android_overlay/AppWatch.kt`):
   collection `log` ({at, kind: now|check|apps, verb, text, item, from}). Chat notes like "started gym", "back home", "woke up"
   or `now: …` are logged on the phone (`NowLog.parse`, no AI; a note with a time is a plan, not a log); "finished X" marks a
   matching task done. Planned tasks get a check-in at the end of their block (`CheckIn.id` = 1.4e9 + nid, kind `checkin`,
   `CheckNote` in ActionReceiver.kt): Done / 15 more min / "Skipped / other" (reply with a "Skipped" chip); answers wait in
   `CheckQueue` and `Store.applyCheck` applies them (skip sets `skipped: day` and drops `planned`). `PlanCheck` compares plan
   and reality; the Plan my day "behind" card and Your day offer "Replan the rest" (`PlanDayPage(replan: true)`). App time
   comes from Android usage access (`AppUsage.sessions`); yesterday's top apps are saved once a day (`Store.noteAppDay`).
   App alarms (collection `appAlarms` {pkg, name, when: open|today|sitting, min, ring, text}; Clock → Alarm → About an app)
   run in `AppWatchService` (foreground, specialUse, polls every 3 s while the screen is on), started by `Clock.sync`
   and on boot. Untested on a phone.
   Plan my day (`lib/day_planner.dart`, `lib/plan_day_page.dart`) is the one place to plan any day. Pieces are tasks (id) and
   habits (minus the id; `DayPlanner.habitTasks`, quick when they have no `planMin`). Tasks may carry `winFrom`/`winTo` (minutes
   after midnight), `estMax` (longest length), `chunk` (done in blocks: Apply makes part items with `partOf`; the last done part
   finishes the task, `Store.markDone`), `dayPri` ({day, p}: importance for one day), and `planned: 'YYYY-MM-DD'` (keeps its time).
   Links (`lib/needs.dart` pure, `lib/piece_facts.dart`, `lib/needs_editor.dart`): `needs` and `doneIf` on a task or habit are
   `{any, if: [check]}` with checks `done` (piece id, `not`), `balance`, `countdown`. States: met, after (placed after what it
   follows), standby (fallback, no time), off. A linked item's reminder is scheduled only while its needs are met
   (`Store.syncRecord`, `syncNeeds` on every save and minute tick); `doneIf` is applied in `Store._autoDone` (no undo entry).
   The page: tray with Tasks / Habits / Conditions chips (tap adds to the day, hold-drag onto a piece links), piece cards, Now card,
   sections Doesn't fit / Quick / On standby / Not today. Not built: place and timer conditions (no "where am I now" state yet).
   Task form (`lib/task_sheet.dart`) is a full page: name + "takes time or quick", the rest under More options; Location's map
   button picks a saved place (arrive/leave reminder optional). Map tiles come from CARTO (OSM's servers block apps).
   Widget tests run the plan page and the form at 360x720 to catch overflow. Untested on a phone.
   Rules and links (`lib/rules.dart` pure, `lib/rule_runner.dart`, `lib/rules_page.dart`, collection `rules`): "when X, if Y, do Z".
   Every `Store.save` compares `Rules.seen` keys (new tx/rentPays/loans/items, done items, done habit days) with the last save and
   runs matching rules; `ruleTick` (every minute and on resume) does `time` rules and finished events, so time rules only run while
   Jarvis is open or when it next opens. A rule's own changes set off no rule (`ruleBusy`); data merged by sync or a backup sets
   off nothing. Each firing is one Activity entry with Undo and a SnackBar (`ruleNotice`). Built-in links are rules with fixed ids
   -101.. (rent→Money, lend→expense, take→income, paying a bill ticks its task), off by default. The AI and ChatGPT write
   `type: rule` items (`Rules.aiSpec`, `docs/chatgpt-project.md`). More → Rules and links. Untested on a phone.
   Voice and "About me" (`lib/about_me.dart` pure, `lib/about_me_page.dart`, collections `words` and `profile`): a mic in the Home
   chat bar (`Native.hear` → the phone's speech screen via MainActivity) puts the transcript in the box to check before sending.
   Your words ({from, to}) are fixed in every note before it is read (`Brain._understand`, original kept as `heard`) and sent to the
   phone's recogniser as hints (`speech_hints`, EXTRA_BIASING_STRINGS, Android 13+). Hold a message → "Fix a word"; editing a message
   that changes 1-3 words offers to add them. Profile files ({name, keys, always, text}) go into the AI prompt only when a key word is
   in the note (`ProfileFiles.pick`, 2400 chars max); ChatGPT writes them as `profile` items; "Copy for ChatGPT to update". Untested on a phone.
5. Groq web answers show no source links (response shape unconfirmed).
6. Calendar, deferred: custom repeats, find free time, global search, weekly review, what-if planning.
7. Known limits: imported times with a named time zone are read as local.
