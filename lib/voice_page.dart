import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'haptics.dart';
import 'home_screen.dart' show logCommand;
import 'native.dart';
import 'store.dart';
import 'voice_replies_page.dart';

/// "Hey Jarvis" wake word, phone actions, and your own names and phrases for them.
class VoicePage extends StatefulWidget {
  const VoicePage({super.key, required this.store});
  final Store store;

  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> with WidgetsBindingObserver {
  Store get s => widget.store;
  final _try = TextEditingController();
  Map<String, bool> _access = {};

  double get _threshold => double.tryParse(s.local('wake_threshold') ?? '') ?? 0.5;
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

  /// Adds a nickname, or edits [old] (its key).
  Future<void> _addNickname([String? old]) async {
    final people = Map<String, dynamic>.from((_shortcuts['people'] as Map?) ?? {});
    final nick = TextEditingController(text: old);
    final who = TextEditingController(text: old == null ? null : '${people[old]}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(old == null ? 'Nickname' : 'Edit nickname'),
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
    if (old != null) people.remove(old);
    sc['people'] = {...people, nick.text.trim().toLowerCase(): who.text.trim()};
    Haptics.tap();
    await _saveShortcuts(sc);
  }

  /// Adds one of your own commands, or edits [old] (its phrase).
  Future<void> _addPhrase([String? old]) async {
    final phrases = Map<String, dynamic>.from((_shortcuts['phrases'] as Map?) ?? {});
    final was = old == null ? const <String, dynamic>{} : Map<String, dynamic>.from(phrases[old] as Map);
    final phrase = TextEditingController(text: old);
    final target = TextEditingController(text: was['target'] as String?);
    final text = TextEditingController(text: was['text'] as String?);
    var kind = (was['kind'] as String?) ?? 'app';
    var speak = was['speak'] != false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(old == null ? 'Your own command' : 'Edit command'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: phrase, autofocus: true, decoration: const InputDecoration(labelText: 'When I say, like "study music"')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Do this'),
                items: const [
                  DropdownMenuItem(value: 'do', child: Text('Jarvis commands, one or more')),
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
                    'do' => 'Commands, like: silent mode then set an alarm for 6:30',
                    'app' => 'App name',
                    'link' => 'Link (https://…)',
                    _ => 'Person (nickname, contact or number)',
                  },
                  labelStyle: const TextStyle(overflow: TextOverflow.visible),
                  helperText: kind == 'do' ? 'Separate steps with "then". Any command from the list below works.' : null,
                  helperMaxLines: 2,
                ),
              ),
              if (kind == 'wa_chat') ...[
                const SizedBox(height: 12),
                TextField(controller: text, decoration: const InputDecoration(labelText: 'Message to fill in (optional)')),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Say what it did'),
                subtitle: const Text('Off: does it quietly'),
                value: speak,
                onChanged: (v) => setD(() => speak = v),
              ),
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
    if (old != null) phrases.remove(old);
    sc['phrases'] = {
      ...phrases,
      phrase.text.trim().toLowerCase().replaceAll(RegExp(r'[.!?]+$'), ''): {
        'kind': kind,
        'target': target.text.trim(),
        if (kind == 'wa_chat' && text.text.trim().isNotEmpty) 'text': text.text.trim(),
        if (!speak) 'speak': false,
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

  static const _kindName = {
    'do': 'Runs',
    'app': 'Opens',
    'link': 'Opens link',
    'wa_chat': 'WhatsApp chat',
    'wa_call': 'WhatsApp call',
    'call': 'Calls',
  };

  /// Everything Jarvis understands, for the "What you can say" list.
  static const _canSay = [
    ('Apps and people', 'open YouTube · message Oishi on WhatsApp saying I\'m on my way · call Oishi on WhatsApp · '
        'video call Oishi on WhatsApp · call Ammu · text Ammu saying I\'m late'),
    ('Music and sound', 'pause · play · next song · previous song · volume up · volume down · set volume to 40% · '
        'mute · play Arijit Singh on Spotify · play lofi on YouTube Music · play lofi on YouTube'),
    ('Phone', 'silent mode · vibrate mode · sound on · do not disturb on · flashlight on · take a selfie · '
        'what time is it · how much battery is left'),
    ('Time', 'set a timer for 10 minutes · cancel the timer · wake me up at 6:30 · set an alarm for 7 pm'),
    ('Places', 'directions to Dhanmondi 27'),
    ('Jarvis', 'stop (stops talking) · anything else, like "what\'s my day" or "spent 200 on lunch", goes to '
        'Jarvis, which answers'),
  ];

  /// How to put "Talk to Jarvis" on a button, like the Essential Key on Nothing phones.
  Widget _button(TextTheme tt, ColorScheme scheme) {
    Widget copy(String label, String value) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          subtitle: Text(value, style: const TextStyle(fontFamily: 'monospace')),
          trailing: IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              Haptics.tap();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied $value')));
            },
          ),
        );
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.smart_button_outlined),
      title: const Text('Talk to Jarvis with a button'),
      subtitle: const Text('Like the Essential Key: press, speak, done. No wake word, mic off the rest of the time.'),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Jarvis has a second icon in your app list, "Talk to Jarvis". An app that lets you pick an app for a button '
          '(like The Everything Key) can only remember "Jarvis", so picking Jarvis there opens Talk to Jarvis; the '
          'card has an Open Jarvis link for the chat. The home screen icon still opens the app.\n\n'
          'For double and long press, Key Mapper can open these instead (Intent, Activity):',
          style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        copy('Listen', 'com.towkirhs.jarcis.TALK'),
        copy('Photo to Jarvis (receipt, bill, note)', 'com.towkirhs.jarcis.SNAP'),
        copy('Run one of your own commands (extra "text" = the phrase)', 'com.towkirhs.jarcis.DO'),
        copy('App package', 'com.towkirhs.jarcis'),
      ],
    );
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
            'Say "Hey Jarvis" or press your button, then a command: "open YouTube", "pause", "set a timer for 10 '
            'minutes", "message Oishi on WhatsApp". Anything else goes to Jarvis, which answers. You can type the '
            'same commands in the chat.',
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Listen for "Hey Jarvis"'),
            subtitle: const Text('Heard on this phone only, no account or key needed. Shows a small notification while '
                'listening. Turn it on again after restarting the phone.'),
            value: wakeOn,
            onChanged: (v) async {
              Haptics.toggle(v);
              if (v && _access['mic'] != true) {
                await Native.requestVoicePermissions();
                await Future<void>.delayed(const Duration(seconds: 1));
              }
              await Native.wake(v, threshold: _threshold);
              await Future<void>.delayed(const Duration(milliseconds: 500));
              _refresh();
            },
          ),
          const SizedBox(height: 8),
          Text('How easily it wakes', style: tt.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<double>(
            segments: const [
              ButtonSegment(value: 0.7, label: Text('Strict')),
              ButtonSegment(value: 0.5, label: Text('Normal')),
              ButtonSegment(value: 0.3, label: Text('Easy')),
              ButtonSegment(value: 0.15, label: Text('Easiest')),
            ],
            selected: {_threshold},
            onSelectionChanged: (v) async {
              Haptics.segment();
              await s.setLocal('wake_threshold', '${v.first}');
              setState(() {});
              // Takes effect now if it is listening.
              if (wakeOn) {
                await Native.wake(false);
                await Native.wake(true, threshold: v.first);
              }
            },
          ),
          const SizedBox(height: 4),
          Text('Easy if it often misses you, Strict if it wakes up by itself. Wake word model: openWakeWord.',
              style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Text('Language you speak to Jarvis in', style: tt.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'en-IN', label: Text('English')),
              ButtonSegment(value: 'bn-BD', label: Text('বাংলা')),
              ButtonSegment(value: '', label: Text("Phone's")),
            ],
            selected: {s.local('speech_lang') ?? 'en-IN'},
            onSelectionChanged: (v) async {
              Haptics.segment();
              await s.setLocal('speech_lang', v.first);
              await Native.speechLang(v.first);
              setState(() {});
            },
          ),
          const SizedBox(height: 4),
          Text('English is tuned for South Asian accents and handles some Banglish. Phone\'s uses your phone language.',
              style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          _button(tt, scheme),
          const SizedBox(height: 8),
          Text('Talking back', style: tt.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Voice replies'),
            subtitle: Text('${VoiceRepliesPage.summary(s)}. When, what and how Jarvis speaks.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => VoiceRepliesPage(store: s)));
              if (mounted) setState(() {});
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
              onTap: () => _addNickname(e.key),
              trailing: IconButton(tooltip: 'Delete', icon: const Icon(Icons.close), onPressed: () => _remove('people', e.key)),
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
              subtitle: Text('${_kindName[(e.value as Map)['kind']] ?? (e.value as Map)['kind']}: ${(e.value as Map)['target']}'
                  '${(e.value as Map)['speak'] == false ? ' · quiet' : ''}'),
              onTap: () => _addPhrase(e.key),
              trailing: IconButton(tooltip: 'Delete', icon: const Icon(Icons.close), onPressed: () => _remove('phrases', e.key)),
            ),
          const SizedBox(height: 16),
          Text('Try a command', style: tt.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _try,
            textInputAction: TextInputAction.go,
            decoration: InputDecoration(
              hintText: 'open WhatsApp',
              suffixIcon: IconButton(tooltip: 'Try it',
                icon: const Icon(Icons.play_arrow),
                onPressed: () async {
                  final t = _try.text.trim();
                  if (t.isEmpty) return;
                  final did = await Native.command(t);
                  if (did != null) logCommand(s, t, did.isEmpty ? 'Okay, quiet.' : did);
                  setState(() => _result = did ?? 'Not a command: Jarvis would treat that as a note.');
                },
              ),
            ),
          ),
          if (_result != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_result!)),
          const SizedBox(height: 16),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.list_alt),
            title: const Text('What you can say'),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (group, lines) in _canSay)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(group, style: tt.labelLarge),
                    const SizedBox(height: 2),
                    Text(lines, style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  ]),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
