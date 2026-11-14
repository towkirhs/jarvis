import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'about_me.dart';
import 'haptics.dart';
import 'native.dart';
import 'store.dart';

/// Gives the phone's speech recogniser your words as hints. Call after the word list changes, and at start.
Future<void> sendSpeechHints(Store s) =>
    Native.speechHints([for (final w in s.list('words')) '${w['to']}'.trim()].where((w) => w.isNotEmpty).toSet().toList());

/// Adds "heard → meant" to your words (replacing an older entry for the same heard words). Returns its id.
int addWord(Store s, String from, String to) {
  final list = s.list('words');
  final undo = <Rec>[];
  for (final old in list.where((w) => '${w['from']}'.toLowerCase() == from.toLowerCase()).toList()) {
    undo.add({'op': 'put', 'col': 'words', 'rec': copyRec(old)});
    list.remove(old);
  }
  final rec = {'id': s.nextId(), 'from': from.trim(), 'to': to.trim()};
  list.add(rec);
  undo.add({'op': 'rm', 'col': 'words', 'id': rec['id']});
  s.logAction('Added to your words: $from → $to', undo);
  s.save();
  sendSpeechHints(s);
  return rec['id'] as int;
}

/// Asks what [heard] should be, and adds it to your words. Returns the meant text, or null if cancelled.
Future<String?> askWord(BuildContext context, Store s, String heard, {String? meant}) async {
  final from = TextEditingController(text: heard);
  final to = TextEditingController(text: meant ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add to your words'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: from, decoration: const InputDecoration(labelText: 'What the phone heard')),
        const SizedBox(height: 12),
        TextField(controller: to, autofocus: meant == null, decoration: const InputDecoration(labelText: 'What you meant')),
        const SizedBox(height: 8),
        const Text('From now on Jarvis fixes this by itself.'),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
      ],
    ),
  );
  if (ok != true || from.text.trim().isEmpty || to.text.trim().isEmpty) return null;
  addWord(s, from.text, to.text);
  Haptics.success();
  return to.text.trim();
}

/// Your words and your profile files: what Jarvis uses to understand how you talk.
class AboutMePage extends StatelessWidget {
  const AboutMePage({super.key, required this.store});
  final Store store;

  Future<void> _editFile(BuildContext context, Rec? old) async {
    final name = TextEditingController(text: '${old?['name'] ?? ''}');
    final keys = TextEditingController(text: ((old?['keys'] as List?) ?? const []).join(', '));
    final text = TextEditingController(text: '${old?['text'] ?? ''}');
    var always = old?['always'] == true;
    final save = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => Scaffold(
            appBar: AppBar(
              title: Text(old == null ? 'New profile file' : 'Profile file'),
              actions: [
                if (old != null)
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      store.removeRec('profile', old, 'Deleted profile file: ${old['name']}');
                      Navigator.pop(ctx, false);
                    },
                  ),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
              ],
            ),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name, like Routines or Money')),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use with every note'),
                subtitle: const Text('For short files like "How I talk". Others are used only when a key word comes up.'),
                value: always,
                onChanged: (v) => setS(() => always = v),
              ),
              if (!always)
                TextField(controller: keys, decoration: const InputDecoration(labelText: 'Key words, separated by commas')),
              const SizedBox(height: 12),
              TextField(
                controller: text,
                minLines: 8,
                maxLines: 20,
                decoration: const InputDecoration(labelText: 'What Jarvis should know', alignLabelWithHint: true),
              ),
              const SizedBox(height: 8),
              Text('Keep it short: a small AI reads only a little at a time.', style: Theme.of(ctx).textTheme.bodySmall),
            ]),
          ),
        ),
      ),
    );
    if (save != true || name.text.trim().isEmpty || text.text.trim().isEmpty) return;
    final f = {
      'name': name.text.trim(),
      'always': always,
      'keys': [for (final k in keys.text.split(',')) if (k.trim().isNotEmpty) k.trim()],
      'text': text.text.trim(),
    };
    if (old == null) {
      final rec = {'id': store.nextId(), ...f};
      store.list('profile').add(rec);
      store.logAction('New profile file: ${f['name']}', [{'op': 'rm', 'col': 'profile', 'id': rec['id']}]);
      store.save();
    } else {
      await store.updateRec('profile', old, 'Changed profile file: ${f['name']}', (x) => x.addAll(f));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('About me')),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('Profile file'),
          onPressed: () => _editFile(context, null),
        ),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final tt = Theme.of(context).textTheme;
            final scheme = Theme.of(context).colorScheme;
            final words = store.list('words');
            final files = store.list('profile');
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              Text('Your words', style: tt.titleMedium),
              Text('What the phone hears, and what you meant. Jarvis fixes these before reading a note, and gives the '
                  'phone your words as hints. Add one here, or hold a message in the chat and tap "Fix a word".',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              for (final w in words)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${w['from']}  →  ${w['to']}'),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      store.removeRec('words', w, 'Removed from your words: ${w['from']}');
                      sendSpeechHints(store);
                    },
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add a word'),
                  onPressed: () => askWord(context, store, ''),
                ),
              ),
              const SizedBox(height: 16),
              Text('Profile files', style: tt.titleMedium),
              Text('Short notes about you: how you talk, your routines, work, people, money. With each note Jarvis '
                  'sends the AI only the files whose key words come up, so even the small phone AI knows you. '
                  'Your ChatGPT Project can write them: paste its JARVIS v1 block in the chat.',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              for (final f in files)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${f['name']}'),
                  subtitle: Text(
                    f['always'] == true ? 'Used with every note' : 'When you mention: ${((f['keys'] as List?) ?? const []).join(', ')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _editFile(context, f),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy for ChatGPT to update'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: ProfileFiles.forChatGpt(files, words)));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied. Paste it in your ChatGPT Project and ask it to update them.')));
                    }
                  },
                ),
              ),
            ]);
          },
        ),
      );
}
