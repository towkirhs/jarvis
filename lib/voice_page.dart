import 'dart:convert';

import 'package:flutter/material.dart';

import 'haptics.dart';
import 'home_screen.dart' show logCommand;
import 'native.dart';
import 'store.dart';

/// "Jarvis" wake word, phone actions, and your own names and phrases for them.
class VoicePage extends StatefulWidget {
  const VoicePage({super.key, required this.store});
  final Store store;

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> with WidgetsBindingObserver {
  Store get s => widget.store;
  late final _key = TextEditingController(text: s.local('picovoice'));
  final _try = TextEditingController();
  Map<String, bool> _access = {};
  String? _result;

  /// {people: {nickname: contact name or number}, apps: {name: app label}, phrases: {phrase: {kind, target, text}}}
  Map<String, dynamic> get _shortcuts => Map<String, dynamic>.from((s.settings['shortcuts'] as Map?) ?? {});

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(); // back from a permission screen
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _key.dispose();
    _try.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final a = await Native.voiceAccess();
    if (mounted) setState(() => _access = a);
  }

  Future<void> _saveShortcuts(Map<String, dynamic> sc) async {
    s.settings['shortcuts'] = sc;
    s.save();
    await Native.setShortcuts(jsonEncode(sc));
    setState(() {});
  }

  Future<void> _addNickname() async {
    final nick = TextEditingController();
    final who = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nickname'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nick, autofocus: true, decoration: const InputDecoration(labelText: 'What you say, like Oishi or Ammu')),
          const SizedBox(height: 12),
          TextField(controller: who, decoration: const InputDecoration(labelText: 'Contact name as saved, or a number')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || nick.text.trim().isEmpty || who.text.trim().isEmpty) return;
    final sc = _shortcuts;
    sc['people'] = {...((sc['people'] as Map?) ?? {}), nick.text.trim().toLowerCase(): who.text.trim()};
    Haptics.tap();
    await _saveShortcuts(sc);
  }

  Future<void> _addPhrase() async {
    final phrase = TextEditingController();
    final target = TextEditingController();
    final text = TextEditingController();
    var kind = 'app';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Your own command'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: phrase, autofocus: true, decoration: const InputDecoration(labelText: 'When I say, like "study music"')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Do this'),
                items: const [
                  DropdownMenuItem(value: 'app', child: Text('Open an app')),
                  DropdownMenuItem(value: 'link', child: Text('Open a link')),
                  DropdownMenuItem(value: 'wa_chat', child: Text('WhatsApp chat with')),
                  DropdownMenuItem(value: 'wa_call', child: Text('WhatsApp call')),
                  DropdownMenuItem(value: 'call', child: Text('Phone call')),
                ],
                onChanged: (v) => setD(() => kind = v ?? kind),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: target,
                decoration: InputDecoration(
                  labelText: switch (kind) {
                    'app' => 'App name',
                    'link' => 'Link (https://…)',
                    _ => 'Person (nickname, contact or number)',
                  },
                ),
              ),
              if (kind == 'wa_chat') ...[
                const SizedBox(height: 12),
                TextField(controller: text, decoration: const InputDecoration(labelText: 'Message to fill in (optional)')),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || phrase.text.trim().isEmpty || target.text.trim().isEmpty) return;
    final sc = _shortcuts;
    sc['phrases'] = {
      ...((sc['phrases'] as Map?) ?? {}),
      phrase.text.trim().toLowerCase().replaceAll(RegExp(r'[.!?]+$'), ''): {
        'kind': kind,
        'target': target.text.trim(),
        if (text.text.trim().isNotEmpty) 'text': text.text.trim(),
      },
    };
    Haptics.tap();
    await _saveShortcuts(sc);
  }

  Future<void> _remove(String group, String key) async {
    final sc = _shortcuts;
    final m = Map<String, dynamic>.from((sc[group] as Map?) ?? {})..remove(key);
    sc[group] = m;
    Haptics.warn();
    await _saveShortcuts(sc);
  }

  Widget _check(String label, bool ok, String button, VoidCallback onTap) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked,
            color: ok ? Theme.of(context).colorScheme.primary : null),
        title: Text(label),
        trailing: ok ? null : TextButton(onPressed: onTap, child: Text(button)),
      );

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final sc = _shortcuts;
    final people = Map<String, dynamic>.from((sc['people'] as Map?) ?? {});
    final phrases = Map<String, dynamic>.from((sc['phrases'] as Map?) ?? {});
    final wakeOn = _access['wake'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Hey Jarvis')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Text(
            'Say "Jarvis", then a command: "open YouTube", "message Oishi on WhatsApp saying I\'m on my way", '
            '"call Oishi on WhatsApp", "call Ammu", "turn on the flashlight", "directions to Dhanmondi 27". '
            'Anything else becomes a note for Jarvis. You can type the same commands in the chat.',
            style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            'Safe by design: messages open with the text filled in and you press send; calls wait 3 seconds '
            'with a Cancel button; the wake word is detected on the phone and nothing is recorded.',
            style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text('Allow', style: tt.titleMedium),
          _check('Microphone, contacts and calls', _access['mic'] == true && _access['contacts'] == true,
              'Allow', () async {
            await Native.requestVoicePermissions();
            await Future<void>.delayed(const Duration(seconds: 1));
            _refresh();
          }),
          _check('Display over other apps (to open apps while you are elsewhere)', _access['overlay'] == true, 'Open',
              Native.openOverlaySettings),
          const SizedBox(height: 16),
          Text('Wake word', style: tt.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _key,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Picovoice AccessKey',
              helperText: 'Free for personal use: sign up at console.picovoice.ai and copy your AccessKey.',
              helperMaxLines: 2,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Listen for "Jarvis"'),
            subtitle: const Text('Shows a small notification while listening. Turn it on again after restarting the phone.'),
            value: wakeOn,
            onChanged: (v) async {
              Haptics.toggle(v);
              final key = _key.text.trim();
              if (v && key.isEmpty) {
                Haptics.reject();
                setState(() => _result = 'Paste your Picovoice AccessKey first.');
                return;
              }
              if (v && _access['mic'] != true) {
                await Native.requestVoicePermissions();
                await Future<void>.delayed(const Duration(seconds: 1));
              }
              await s.setLocal('picovoice', key);
              await Native.wake(v, key: key);
              await Future<void>.delayed(const Duration(milliseconds: 500));
              _refresh();
            },
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text('Nicknames', style: tt.titleMedium)),
            TextButton.icon(onPressed: _addNickname, icon: const Icon(Icons.add), label: const Text('Add')),
          ]),
          if (people.isEmpty)
            Text('Jarvis looks people up in your contacts. Add a nickname when you call someone by another name.',
                style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          for (final e in people.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(e.key),
              subtitle: Text('${e.value}'),
              trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => _remove('people', e.key)),
            ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text('Your own commands', style: tt.titleMedium)),
            TextButton.icon(onPressed: _addPhrase, icon: const Icon(Icons.add), label: const Text('Add')),
          ]),
          for (final e in phrases.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bolt),
              title: Text('"${e.key}"'),
              subtitle: Text('${(e.value as Map)['kind']}: ${(e.value as Map)['target']}'),
              trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => _remove('phrases', e.key)),
            ),
          const SizedBox(height: 16),
          Text('Try a command', style: tt.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _try,
            textInputAction: TextInputAction.go,
            decoration: InputDecoration(
              hintText: 'open WhatsApp',
              suffixIcon: IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () async {
                  final t = _try.text.trim();
                  if (t.isEmpty) return;
                  final did = await Native.command(t);
                  if (did != null) logCommand(s, t, did);
                  setState(() => _result = did ?? 'Not a command: Jarvis would treat that as a note.');
                },
              ),
            ),
          ),
          if (_result != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_result!)),
        ],
      ),
    );
  }
}
