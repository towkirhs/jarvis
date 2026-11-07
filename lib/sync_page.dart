import 'package:flutter/material.dart';

import 'haptics.dart';
import 'store.dart';
import 'sync.dart';

/// Turn on encrypted sync through a private GitHub Gist.
class SyncPage extends StatefulWidget {
  const SyncPage({super.key, required this.store});
  final Store store;

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final _token = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _busy = false;
  String? _message;

  Store get s => widget.store;

  @override
  void dispose() {
    _token.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _go(Future<String?> Function() job) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final m = await job();
      _message = m;
    } catch (e) {
      Haptics.reject();
      _message = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _turnOn() async {
    if (_token.text.trim().isEmpty) return setState(() => _message = 'Paste a GitHub token first.');
    if (_pass.text.length < 8) return setState(() => _message = 'Use a passphrase of at least 8 characters.');
    if (_pass.text != _pass2.text) return setState(() => _message = 'The two passphrases are different.');
    await _go(() => Sync.setUp(s, _token.text.trim(), _pass.text));
    _pass.clear();
    _pass2.clear();
  }

  Future<void> _turnOff() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off sync?'),
        content: const Text('Your data stays on this phone and in the encrypted copy on GitHub. '
            'This phone just stops syncing.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Turn off')),
        ],
      ),
    );
    if (ok != true) return;
    await Sync.turnOff(s);
    setState(() => _message = 'Sync is off on this phone.');
  }

  @override
  Widget build(BuildContext context) {
    final on = Sync.enabled(s);
    final last = Sync.lastSynced(s);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sync and backup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(on ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                  color: on ? theme.colorScheme.primary : null),
              title: Text(on ? 'Sync is on' : 'Sync is off'),
              subtitle: Text(on
                  ? (last == null ? 'Not synced yet' : 'Last synced ${niceWhen(last.millisecondsSinceEpoch)}')
                  : 'Your data lives only on this phone.'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Jarvis locks your data with your passphrase before it leaves the phone, then keeps it in a private '
            'GitHub Gist. GitHub only sees scrambled bytes. Photos and your Gemini key are not synced.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (!on) ...[
            TextField(
              controller: _token,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'GitHub token',
                helperText: 'github.com → Settings → Developer settings → Tokens (classic), with only "gist" ticked.',
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Passphrase',
                helperText: 'Use the same one on every device. If you lose it, the synced copy cannot be opened.',
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass2,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passphrase again'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _turnOn,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Turn on sync'),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _busy ? null : () => _go(() => Sync.run(s, force: true)),
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _busy ? null : _turnOff, child: const Text('Turn off on this phone')),
          ],
          if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
          if (_message != null)
            Padding(padding: const EdgeInsets.only(top: 16), child: Text(_message!, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}
