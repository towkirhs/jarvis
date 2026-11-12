import 'package:flutter/material.dart';

import 'phone_calendar.dart';
import 'phone_sync.dart';
import 'store.dart';

/// Shows the phone's calendars (Google Calendar and any other account on the phone) inside Jarvis, and adds
/// Jarvis events to one of them, so they appear everywhere that calendar does.
class PhoneCalendarPage extends StatefulWidget {
  const PhoneCalendarPage({super.key, required this.store});
  final Store store;

  @override
  State<PhoneCalendarPage> createState() => _PhoneCalendarPageState();
}

class _PhoneCalendarPageState extends State<PhoneCalendarPage> with WidgetsBindingObserver {
  Store get s => widget.store;
  bool _allowed = false;
  bool _busy = false;
  String _status = '';
  List<Map<String, dynamic>> _calendars = [];

  Map<String, dynamic> get _cfg => PhoneSync.config(s);

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

  /// Back from Android's permission screen: look again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final ok = await PhoneCalendarApi.access();
    final list = ok ? await PhoneCalendarApi.calendars() : <Map<String, dynamic>>[];
    if (mounted) {
      setState(() {
        _allowed = ok;
        _calendars = list;
      });
    }
  }

  Future<void> _save(Map<String, dynamic> cfg) async {
    await PhoneSync.saveConfig(s, cfg);
    if (mounted) setState(() {});
  }

  Future<void> _sync() async {
    setState(() => _busy = true);
    final t = await PhoneSync.run(s);
    if (mounted) {
      setState(() {
        _busy = false;
        _status = t;
      });
    }
  }

  Future<void> _toggle(bool on) async {
    if (on && !_allowed) {
      await PhoneCalendarApi.request();
      await _save({..._cfg, 'on': true});
      return;
    }
    await _save({..._cfg, 'on': on});
    if (on) {
      await _sync();
    } else {
      PhoneSync.clear(s);
      setState(() => _status = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = _cfg['on'] == true;
    final read = {for (final id in (_cfg['read'] as List?) ?? const []) id as int};
    final writeTo = _cfg['writeTo'] as int?;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Phone calendar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          SwitchListTile(
            title: const Text("Use the phone's calendar"),
            subtitle: Text(_allowed || !on ? 'Google Calendar and other accounts on this phone' : 'Allow calendar access when Android asks'),
            value: on,
            onChanged: _toggle,
          ),
          if (on && !_allowed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('Jarvis is not allowed to use the calendar yet.', style: TextStyle(color: scheme.error)),
            ),
          if (on && _allowed) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Show in Jarvis', style: text.titleSmall),
            ),
            for (final c in _calendars)
              CheckboxListTile(
                secondary: Container(width: 14, height: 14, decoration: BoxDecoration(color: Color(c['color'] as int), shape: BoxShape.circle)),
                title: Text(c['name'] as String),
                subtitle: Text(c['account'] as String),
                value: read.contains(c['id']),
                onChanged: (v) async {
                  final next = {...read};
                  v == true ? next.add(c['id'] as int) : next.remove(c['id']);
                  await _save({..._cfg, 'read': next.toList()});
                  await _sync();
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Add my Jarvis events to', style: text.titleSmall),
            ),
            RadioGroup<int?>(
              groupValue: writeTo,
              onChanged: (v) async {
                await _save({..._cfg, 'writeTo': v});
                await _sync();
              },
              child: Column(
                children: [
                  const RadioListTile<int?>(title: Text("Don't add them"), value: null),
                  for (final c in _calendars.where((c) => c['writable'] == true))
                    RadioListTile<int?>(title: Text(c['name'] as String), subtitle: Text(c['account'] as String), value: c['id'] as int),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Events you add in Jarvis, and changes to them, are copied to that calendar, and changes made there '
                'come back. Tasks, alarms and habit blocks stay in Jarvis. Turn this on for one phone only, or the '
                'events are added twice.',
                style: text.bodySmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _sync,
                    icon: const Icon(Icons.sync),
                    label: Text(_busy ? 'Syncing' : 'Sync now'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_status, style: text.bodySmall)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
