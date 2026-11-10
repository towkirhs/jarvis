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
- CI often fails with 504s downloading Gradle or Kotlin files. That isn't a code error: re-run the failed job.
- Releases are signed with a fixed key from a repo secret, so they update over each other.

## Overhaul branch
- `overhaul` is a phased revamp aimed at Google Play. Order: voice and understanding → bubble and quick capture →
  look and feel → security and store readiness. It merges to main only after I have tried it on my phone.
- Every push to `overhaul` publishes a pre-release `overhaul-N` with `jarvis-dev.apk`: a separate app
  ("Jarvis Dev", `com.towkirhs.jarcis.dev`) that installs next to the real one with its own empty data.

## Local development (Windows)
- Recreate the Android scaffold the same way CI does (the "Generate scaffold" and "Apply Android overlay" steps
  in the workflow). They are bash commands: run them in Git Bash. Re-copy the overlay after editing Kotlin files.
- Fast checks: `flutter analyze --no-fatal-infos` and `flutter test`; Kotlin: `cd android && ./gradlew :app:testDebugUnitTest`.
- **A local build cannot install over the released app** (different signing key), and uninstalling loses my data.
  Install local builds as a separate app: give the local debug build `applicationIdSuffix = ".dev"`
  (in the generated `android/` only, never in CI). Read phone logs with `adb logcat`.

## Open items
1. UI: make Accounts' "Total balance" row prominent; the Home chips row is cut off on the right;
   animations ignore the reduced-motion setting.
2. Not yet confirmed on my phone: the build-128 Essential Key fix, the "Hey Jarvis" standby fix (build 138),
   voice briefing questions (build 140), ChatGPT blocks (build 143).
3. On `overhaul`, untested on a phone: `untilDone` items (ring daily until marked done), speech language
   setting (default en-IN), listening card retry, notes with before/until/if/every going to the AI.
5. Groq web answers show no source links (response shape unconfirmed).
6. Calendar, deferred: custom repeats, find free time, global search, weekly review, what-if planning.
7. Known limits: repeating events show only the next time; imported times with a named time zone are read as
   local; alarms set from chat use the older notification-style alarm.
