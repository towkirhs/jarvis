import 'dart:convert';

import 'package:flutter/material.dart';

import 'haptics.dart';
import 'native.dart';
import 'store.dart';

/// When and how Jarvis talks back. Kept in settings['speech'] and handed to the phone, which decides each time.
class VoiceRepliesPage extends StatefulWidget {
  const VoiceRepliesPage({super.key, required this.store});
  final Store store;

  static const modes = {
    'voice': ('Only when I spoke to it', 'Answers aloud when you used your voice or the button; quiet when you type'),
    'always': ('Always', 'Also when you type in the app or reply to a notification'),
    'headphones': ('Only with headphones', 'Wired or Bluetooth, so only you hear it'),
    'never': ('Never', 'Text and notifications only'),
  };

  /// "Only when I spoke to it" and the like, for the Hey Jarvis page.
  static String summary(Store s) {
    final m = ((s.settings['speech'] as Map?) ?? {})['mode'] as String? ?? 'voice';
    return modes[m]!.$1;
  }

  @override
  State<VoiceRepliesPage> createState() => _VoiceRepliesPageState();
}

class _VoiceRepliesPageState extends State<VoiceRepliesPage> {
  Store get s => widget.store;
  List<Map<String, String>> _voices = [];

  Map<String, dynamic> get _sp => Map<String, dynamic>.from((s.settings['speech'] as Map?) ?? {});

  @override
  void initState() {
    super.initState();
    _loadVoices();
  }

  /// The speech engine starts on the first ask, so ask again shortly if the list came back empty.
  Future<void> _loadVoices([int tries = 3]) async {
    final v = await Native.voices();
    if (!mounted) return;
    if (v.isEmpty && tries > 0) {
      await Future<void>.delayed(const Duration(seconds: 1));
      return _loadVoices(tries - 1);
    }
    setState(() => _voices = v);
  }

  Future<void> _set(String key, Object? value) async {
    final sp = _sp..[key] = value;
    s.settings['speech'] = sp;
    s.save();
    await Native.setSpeech(jsonEncode(sp));
    setState(() {});
  }

  Future<void> _pickTime(String key, String fallback) async {
    final cur = ((_sp[key] as String?)?.isNotEmpty == true ? _sp[key] as String : fallback).split(':');
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(cur[0]), minute: int.parse(cur[1])));
    if (t != null) await _set(key, '${two(t.hour)}:${two(t.minute)}');
  }

  Widget _group(String name, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
            child: Text(name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
          ),
          Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
        ],
      );

  Widget _switch(String key, String title, String subtitle, {bool fallback = true}) => SwitchListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        value: (_sp[key] as bool?) ?? fallback,
        onChanged: (v) {
          Haptics.toggle(v);
          _set(key, v);
        },
      );

  @override
  Widget build(BuildContext context) {
    final sp = _sp;
    final mode = (sp['mode'] as String?) ?? 'voice';
    final quiet = (sp['quietFrom'] as String?)?.isNotEmpty == true;
    final rate = ((sp['rate'] as num?) ?? 1.0).toDouble();
    final pitch = ((sp['pitch'] as num?) ?? 1.0).toDouble();
    final voice = (sp['voice'] as String?) ?? '';
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Voice replies')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
        children: [
          _group('When Jarvis speaks', [
            RadioGroup<String>(
              groupValue: mode,
              onChanged: (v) {
                Haptics.segment();
                _set('mode', v);
              },
              child: Column(children: [
                for (final e in VoiceRepliesPage.modes.entries)
                  RadioListTile<String>(value: e.key, title: Text(e.value.$1), subtitle: Text(e.value.$2)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('On silent or vibrate it stays quiet, unless headphones are in.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          ]),
          _group('Quiet hours', [
            SwitchListTile(
              title: const Text('Never speak during quiet hours'),
              subtitle: Text(quiet ? '${sp['quietFrom']} to ${sp['quietTo']}' : 'Off'),
              value: quiet,
              onChanged: (v) async {
                Haptics.toggle(v);
                await _set('quietFrom', v ? '23:00' : '');
                await _set('quietTo', v ? '07:00' : '');
              },
            ),
            if (quiet)
              Row(children: [
                Expanded(
                  child: ListTile(
                    title: const Text('From'),
                    trailing: Text('${sp['quietFrom']}'),
                    onTap: () => _pickTime('quietFrom', '23:00'),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    title: const Text('To'),
                    trailing: Text('${sp['quietTo']}'),
                    onTap: () => _pickTime('quietTo', '07:00'),
                  ),
                ),
              ]),
          ]),
          _group('What it says', [
            _switch('confirm', 'Confirmations', '"Opening YouTube", "Calling Oishi in 3 seconds"'),
            _switch('answer', 'Answers', 'Replies to your questions and notes'),
            _switch('problem', 'Problems', '"I couldn\'t find Oishi in your contacts"'),
            _switch('short', 'Short answers', 'Just the first sentence; the rest is in the notification'),
            _switch('followUp', 'Listen for a follow-up', 'After answering you aloud, it listens a few seconds more'),
          ]),
          _group('How it sounds', [
            ListTile(
              title: const Text('Voice'),
              subtitle: Text(_voices.isEmpty ? "The phone's default voice" : 'Voices on this phone'),
              trailing: _voices.isEmpty
                  ? null
                  : DropdownButton<String>(
                      value: _voices.any((v) => v['name'] == voice) ? voice : '',
                      underline: const SizedBox.shrink(),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Default')),
                        for (var i = 0; i < _voices.length; i++)
                          DropdownMenuItem(value: _voices[i]['name'], child: Text('${_voices[i]['locale']} ${i + 1}')),
                      ],
                      onChanged: (v) => _set('voice', v ?? ''),
                    ),
            ),
            ListTile(title: const Text('Speed'), trailing: Text('${rate.toStringAsFixed(1)}×')),
            Slider(
              value: rate,
              min: 0.5,
              max: 2,
              divisions: 15,
              onChanged: (v) => setState(() => s.settings['speech'] = _sp..['rate'] = v),
              onChangeEnd: (v) => _set('rate', v),
            ),
            ListTile(title: const Text('Pitch'), trailing: Text('${pitch.toStringAsFixed(1)}×')),
            Slider(
              value: pitch,
              min: 0.5,
              max: 2,
              divisions: 15,
              onChanged: (v) => setState(() => s.settings['speech'] = _sp..['pitch'] = v),
              onChangeEnd: (v) => _set('pitch', v),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.record_voice_over_outlined),
                label: const Text('Test voice'),
                onPressed: () => Native.speakTest("Hi, I'm Jarvis. Your next alarm is at six thirty."),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Text('To stop Jarvis mid-sentence: tap Stop on its card, press your button, or say "stop".',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
