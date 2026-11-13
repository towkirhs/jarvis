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
   Productivity engine (`lib/engine_page.dart`, rules in `lib/productivity.dart`): Eisenhower matrix (priority), Pareto (`vital`),
   time blocking (Plan my day), deep work (Focus "Deep" mode, sessions with `deep: true`), active recall (`cards`, Leitner boxes),
   GTD lists Inbox/Next/Waiting/Someday + weekly review (`settings.gtdReview`). Countdown groups (`group`), calendar 1-day and
   30-day views. All untested on a phone.
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
   tab's FAB opens it too), event view sheet (Edit this date / Skip this date). The grid captures sideways swipes, so main-tab swipe
   does not work over it. Phone calendar two-way sync: More → Phone calendar (needs the calendar permission). Only timed events are
   mirrored; skipped dates are mirrored for timed repeats only; use one phone as the write-to device or events duplicate. Widget tests
   cover the grid in CI; untested on a real phone.
   Plan any day (`lib/day_planner.dart`, `lib/plan_day_page.dart`): `DayPlanner.plan(day:, extra:)`; tasks may carry `winFrom`/`winTo`
   (minutes after midnight, a window to stay inside) and `estMax` (longest length: spare time is given to it after every task has its
   shortest). Window tasks are placed first, earliest end first. Applying stamps `planned: 'YYYY-MM-DD'`: such tasks keep their time when
   the day is opened again ("Place everything again" re-flows). Repeating and phone events are fixed blocks. Overflow tasks say why and
   can move to the next day they fit (up to 21 days ahead) or a picked day. Opened from Plan my day, or the calendar toolbar for the
   day on show. Rules only (no AI); untested on a phone.
5. Groq web answers show no source links (response shape unconfirmed).
6. Calendar, deferred: custom repeats, find free time, global search, weekly review, what-if planning.
7. Known limits: imported times with a named time zone are read as
   local; alarms set from chat use the older notification-style alarm.
