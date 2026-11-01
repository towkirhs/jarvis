import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const JarcisApp());

class JarcisApp extends StatelessWidget {
  const JarcisApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Jarvis',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const SpikePage(),
      );
}

/// Phase 1 spike: prove exact alarms ring and shared text arrives.
class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  static const _channel = MethodChannel('jarcis/spike');
  static final _timePattern =
      RegExp(r'(\d{1,2}):(\d{2})\s*(am|pm)?', caseSensitive: false);

  String _shared = '(nothing shared yet)';
  String _message = '';
  List<String> _rows = [];

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText') _onShared(call.arguments as String);
    });
    _start();
  }

  Future<void> _start() async {
    await _channel.invokeMethod('requestNotificationPermission');
    final text = await _channel.invokeMethod<String>('takeSharedText');
    if (text != null) await _onShared(text);
    await _refresh();
  }

  Future<void> _onShared(String text) async {
    setState(() => _shared = text);
    final match = _timePattern.firstMatch(text);
    if (match == null) {
      setState(() => _message = 'No time like 3:15 found in the shared text.');
      return;
    }
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final suffix = match.group(3)?.toLowerCase();
    if (suffix == 'pm' && hour < 12) hour += 12;
    if (suffix == 'am' && hour == 12) hour = 0;
    if (hour > 23 || minute > 59) {
      setState(() => _message = 'Time out of range: $hour:$minute');
      return;
    }
    final now = DateTime.now();
    var when = DateTime(now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    await _schedule(when, text);
  }

  Future<void> _schedule(DateTime when, String label) async {
    final millis = when.millisecondsSinceEpoch;
    await _channel.invokeMethod('schedule', {
      'id': (millis ~/ 1000) % 1000000000,
      'millis': millis,
      'label': label,
    });
    setState(() => _message = 'Alarm set for ${_clock(when)}');
    await _refresh();
  }

  Future<void> _refresh() async {
    final raw = await _channel.invokeMethod<String>('getLog') ?? '';
    final scheduled = <String, List<String>>{};
    final fired = <String, int>{};
    for (final line in raw.split('\n')) {
      final p = line.split('|');
      if (p.length >= 3 && p[0] == 'S') scheduled[p[1]] = p;
      if (p.length >= 3 && p[0] == 'F') fired[p[1]] = int.parse(p[2]);
    }
    final rows = <String>[];
    for (final entry in scheduled.entries.toList().reversed) {
      final target = int.parse(entry.value[2]);
      final at = DateTime.fromMillisecondsSinceEpoch(target);
      final f = fired[entry.key];
      rows.add(f == null
          ? '${_clock(at)}  not fired yet'
          : '${_clock(at)}  fired ${((f - target) / 1000).toStringAsFixed(1)}s after');
    }
    setState(() => _rows = rows);
  }

  String _clock(DateTime t) => t.toString().substring(11, 19);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Jarvis spike')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Last shared text', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(_shared),
            const SizedBox(height: 8),
            Text(_message),
            const SizedBox(height: 16),
            Wrap(spacing: 8, children: [
              FilledButton(
                onPressed: () => _schedule(
                    DateTime.now().add(const Duration(minutes: 1)), 'test alarm'),
                child: const Text('Ring in 1 minute'),
              ),
              OutlinedButton(onPressed: _refresh, child: const Text('Refresh log')),
            ]),
            const SizedBox(height: 16),
            const Text('Alarm log (newest first)', style: TextStyle(fontWeight: FontWeight.bold)),
            for (final r in _rows) Text(r),
          ],
        ),
      );
}
