import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'alarm_settings_page.dart';
import 'backups.dart';
import 'native.dart';
import 'store.dart';

/// One line of the Health check: fine, needs fixing, or just for your information.
class HealthRow {
  const HealthRow(this.title, this.detail, {required this.state, this.fix});
  final String title;
  final String detail;

  /// ok, fix or info.
  final String state;

  /// What [Native.openHealthFix] (or a Jarvis page) opens to put it right.
  final String? fix;
}

/// Turns what the phone reports into the Health check's lines. Pure, so it can be tested.
class HealthCheck {
  static List<HealthRow> rows(
    Map<String, dynamic> phone, {
    required DateTime now,
    String? lastBackupDay,
    bool appAlarms = false,
  }) {
    bool on(String k) => phone[k] == true;
    HealthRow check(String k, String good, String bad, String fix) =>
        on(k) ? HealthRow(good, '', state: 'ok') : HealthRow(bad.split('|').first, bad.split('|').last, state: 'fix', fix: fix);
    final out = [
      check('notifications', 'Notifications are on', 'Notifications are off|Reminders, check-ins and alarms on tasks cannot show.', 'notifications'),
      check('exact', 'Alarms can ring on the minute', 'Exact alarms are not allowed|Alarms may ring minutes late. Allow "Alarms and reminders".', 'exact'),
      check('battery', 'Battery: not restricted', 'Battery saving can stop Jarvis|Open Jarvis\'s app page, then Battery, and choose Unrestricted.', 'app'),
      check('overlay', 'Can show over other apps', 'Cannot show over other apps|The alarm screen cannot appear while you use the phone.', 'overlay'),
      check('fullScreen', 'Can use the full screen', 'Cannot use the full screen|The alarm screen cannot appear on a locked phone.', 'fullScreen'),
    ];
    if (on('usage')) {
      out.add(const HealthRow('Usage access is on', '', state: 'ok'));
    } else {
      out.add(HealthRow(
        'Usage access is off',
        appAlarms ? 'Your app alarms cannot work without it.' : 'Only needed for app time and app alarms.',
        state: appAlarms ? 'fix' : 'info',
        fix: 'usage',
      ));
    }
    out.add(_beat(phone, now));
    if (lastBackupDay != null || !kIsWeb) out.add(_backup(lastBackupDay, now));
    return out;
  }

  static HealthRow _beat(Map<String, dynamic> phone, DateTime now) {
    final at = (phone['beatAt'] as num?)?.toInt() ?? 0;
    final due = (phone['beatDue'] as num?)?.toInt() ?? 0;
    if (at == 0) {
      return const HealthRow('Background test: not run yet', 'It runs by itself every night at 3:30 am. The first result shows tomorrow.',
          state: 'info');
    }
    if (now.millisecondsSinceEpoch - at > 26 * 3600000) {
      return HealthRow(
        'Background test did not run last night',
        'Last ran ${niceWhen(at)}. Android may be stopping Jarvis while the phone sleeps: check Battery above.',
        state: 'fix',
        fix: 'app',
      );
    }
    final late = ((at - due) / 60000).round();
    if (late > 30) {
      return HealthRow(
        'Background test ran ${late >= 120 ? '${(late / 60).round()} h' : '$late min'} late',
        'Ran ${niceWhen(at)}. Deep sleep held it back, so reminders can come late too. Alarms are not affected.',
        state: 'info',
      );
    }
    return HealthRow('Background test ran on time', 'Last ran ${niceWhen(at)}.', state: 'ok');
  }

  static HealthRow _backup(String? day, DateTime now) {
    if (day == null) return const HealthRow('No daily backup yet', 'The first one is made the next time Jarvis is open.', state: 'info');
    final age = DateTime(now.year, now.month, now.day).difference(DateTime.parse(day)).inDays;
    if (age > 2) {
      return HealthRow('Last backup $age days ago', 'Backups are made while Jarvis is open. Open it once a day, or save a backup file.',
          state: 'fix', fix: 'backup');
    }
    return HealthRow('Backed up ${age == 0 ? 'today' : age == 1 ? 'yesterday' : '$age days ago'}', 'The last 14 days are kept on this phone.',
        state: 'ok');
  }
}

/// Settings → Health check: everything alarms, reminders and backups depend on, each with a way to fix it.
class HealthPage extends StatefulWidget {
  const HealthPage({super.key, required this.store});
  final Store store;

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> with WidgetsBindingObserver {
  List<HealthRow>? _rows;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from an Android settings page: look again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final phone = await Native.health();
    var files = const <File>[];
    try {
      files = await Backups.list();
    } catch (_) {
      // No storage to read: shown as "No daily backup yet".
    }
    if (!mounted) return;
    setState(() => _rows = HealthCheck.rows(
          phone,
          now: DateTime.now(),
          lastBackupDay: files.isEmpty ? null : Backups.dayOf(files.first.uri.pathSegments.last),
          appAlarms: widget.store.list('appAlarms').any((a) => a['on'] != false),
        ));
  }

  Future<void> _fix(String what) async {
    switch (what) {
      case 'overlay':
        await Native.openOverlaySettings();
      case 'fullScreen':
        await Native.openFullScreenSettings();
      case 'usage':
        await Native.openUsageAccess();
      case 'backup':
        if (await Backups.saveCopy(widget.store) && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup saved.')));
        }
      default:
        await Native.openHealthFix(what);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rows = _rows;
    final toFix = rows?.where((r) => r.state == 'fix').length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Health check')),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  color: toFix == 0 ? scheme.primaryContainer : scheme.tertiaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Icon(toFix == 0 ? Icons.verified_outlined : Icons.build_circle_outlined,
                          size: 32, color: toFix == 0 ? scheme.primary : scheme.onTertiaryContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          toFix == 0 ? 'All good. Alarms, reminders and backups should work.' : '$toFix thing${toFix == 1 ? '' : 's'} to fix',
                          style: tt.titleMedium?.copyWith(color: toFix == 0 ? null : scheme.onTertiaryContainer),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(children: [
                    for (final r in rows)
                      ListTile(
                        leading: Icon(
                          switch (r.state) { 'ok' => Icons.check_circle, 'fix' => Icons.error_outline, _ => Icons.info_outline },
                          color: switch (r.state) { 'ok' => scheme.primary, 'fix' => scheme.tertiary, _ => scheme.onSurfaceVariant },
                        ),
                        title: Text(r.title),
                        subtitle: r.detail.isEmpty ? null : Text(r.detail),
                        trailing: r.fix != null && r.state != 'ok' ? TextButton(onPressed: () => _fix(r.fix!), child: const Text('Fix')) : null,
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.alarm_on_outlined),
                  title: const Text('Try an alarm'),
                  subtitle: const Text('Ring a test alarm now or in a minute'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AlarmSettingsPage())),
                ),
              ],
            ),
    );
  }
}
