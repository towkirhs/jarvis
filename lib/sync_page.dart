import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'haptics.dart';
import 'store.dart';
import 'sync.dart';
import 'web_notify.dart';

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
  final _code = TextEditingController();
  bool _busy = false;
  String? _message;

  Store get s => widget.store;

  @override
  void dispose() {
    _token.dispose();
    _pass.dispose();
    _pass2.dispose();
    _code.dispose();
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
            'This device just stops syncing.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Turn off')),
        ],
      ),
    );
    if (ok != true) return;
    await Sync.turnOff(s);
    setState(() => _message = 'Sync is off on this device.');
  }

  Future<void> _showCode() async {
    if (Sync.setupCode(s) == null) await _go(() => Sync.run(s, force: true));
    final code = Sync.setupCode(s);
    if (code == null || !mounted) return;
    var shown = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Set up another device'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('On the other device (or the web app at towkirhs.github.io/jarvis), open More → Sync and backup, '
                'and paste this code into "Setup code".'),
            const SizedBox(height: 12),
            Text(
              'Anyone with this code can read your Jarvis data. Paste it only on your own devices, and do not '
              'send it in a chat.',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
            if (shown) ...[
              const SizedBox(height: 12),
              SelectableText(code, maxLines: 4, style: const TextStyle(fontSize: 11)),
            ],
          ]),
          actions: [
            if (!shown) TextButton(onPressed: () => setD(() => shown = true), child: const Text('Show')),
            FilledButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copy code'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                Haptics.success();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Setup code copied.')));
              },
            ),
          ],
        ),
      ),
    );
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
                  : 'Your data lives only on this device.'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Jarvis locks your data with your passphrase before it leaves this device, then keeps it in a private '
            'GitHub Gist. GitHub only sees scrambled bytes. Photos and your Gemini key are not synced.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (kIsWeb)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('On this computer', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  const Text('Install: in Chrome or Edge, open the menu (⋮) and choose "Install Jarvis". It then opens '
                      'in its own window like a desktop app.'),
                  const SizedBox(height: 8),
                  Text(switch (webNotifyPermission()) {
                    'granted' => 'Reminders show as notifications while Jarvis is open in a window or tab.',
                    'denied' => 'Notifications are blocked. Allow them in the site settings (the icon left of the address).',
                    'unsupported' => 'This browser cannot show notifications.',
                    _ => 'Turn on notifications to get reminders while Jarvis is open.',
                  }),
                  if (webNotifyPermission() == 'default')
                    TextButton.icon(
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: const Text('Turn on notifications'),
                      onPressed: () async {
                        await webNotifyAsk();
                        if (mounted) setState(() {});
                      },
                    ),
                ]),
              ),
            )
          else
            Text('Also on your computer: open towkirhs.github.io/jarvis and paste a setup code from here.',
                style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          if (!on) ...[
            Text('Have a setup code from your other device?', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _code,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Setup code',
                helperText: 'On the device where sync is on: Sync and backup → Set up another device.',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : () => _go(() => Sync.joinWithCode(s, _code.text)).then((_) => _code.clear()),
              icon: const Icon(Icons.link),
              label: const Text('Join with code'),
            ),
            const Divider(height: 40),
            Text('Or set it up with a token and passphrase', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
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
            OutlinedButton.icon(
              onPressed: _busy ? null : _showCode,
              icon: const Icon(Icons.devices_outlined),
              label: const Text('Set up another device'),
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
