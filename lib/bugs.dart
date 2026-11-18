import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'haptics.dart';
import 'store.dart';

/// Bug catch: things that went wrong, kept with what you said and what Jarvis did,
/// so they can be sent for fixing in one go. Collection `bugs` {at, note, screen, said, reply, did, via, fixed}.
class Bugs {
  /// A bug about chat message [c] (what you said and what Jarvis answered and did); [note] is what it should have done.
  static Rec fromChat(Store s, Rec? c, String note) => {
        'id': s.nextId(),
        'at': DateTime.now().millisecondsSinceEpoch,
        'note': note.trim(),
        'screen': 'Chat',
        if (c != null) ...{
          'said': c['raw'],
          'reply': c['reply'],
          'did': c['msg'],
          'via': c['via'],
          if (c['commands'] is List) 'commands': c['commands'],
        },
      };

  /// Saves [b] (with Undo in Activity).
  static void add(Store s, Rec b) {
    s.list('bugs').add(b);
    s.logAction('Bug caught: ${b['note']}', [
      {'op': 'rm', 'col': 'bugs', 'id': b['id']},
    ]);
    s.save();
  }

  /// The last chat message before the one being written now: what a "bug: …" note is about.
  static Rec? lastChat(Store s, {int? before}) => s
      .list('captures')
      .where((c) => c['status'] == 'done' && c['source'] != 'journal' && c['id'] != before && !'${c['raw']}'.toLowerCase().startsWith('bug'))
      .lastOrNull;

  /// The open bugs as one text to paste to whoever fixes them.
  static String report(List<Rec> bugs) {
    final open = bugs.where((b) => b['fixed'] != true).toList();
    final out = StringBuffer('Jarvis bugs (${open.length})\n');
    for (final (i, b) in open.indexed) {
      out.writeln('\n${i + 1}. ${b['note']}');
      out.writeln('   Where: ${b['screen'] ?? 'App'} · ${niceWhen(b['at'] as int)}');
      if (b['said'] != null) out.writeln('   I said: ${b['said']}');
      if (b['reply'] != null && '${b['reply']}'.isNotEmpty) out.writeln('   Jarvis said: ${b['reply']}');
      if (b['did'] != null && '${b['did']}'.isNotEmpty) out.writeln('   Jarvis did: ${'${b['did']}'.replaceAll('\n', '; ')}');
      if (b['commands'] is List) out.writeln('   Commands: ${(b['commands'] as List).join(' | ')}');
      if (b['via'] != null) out.writeln('   Read by: ${b['via']}');
    }
    return out.toString().trimRight();
  }
}

/// Asks what should have happened, then catches the bug. [c] is the chat message it is about, if any.
Future<void> catchBug(BuildContext context, Store s, {Rec? chat, String? screen}) async {
  final what = TextEditingController();
  final where = TextEditingController(text: screen ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.bug_report_outlined),
      title: const Text('Catch a bug'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (chat != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('About: "${chat['raw']}"', maxLines: 2, overflow: TextOverflow.ellipsis),
          )
        else
          TextField(controller: where, decoration: const InputDecoration(labelText: 'Where (screen)', hintText: 'Calendar, Money, Your day…')),
        if (chat == null) const SizedBox(height: 12),
        TextField(
          controller: what,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'What went wrong, or what should it do?'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Catch it')),
      ],
    ),
  );
  if (ok != true || what.text.trim().isEmpty) return;
  final b = Bugs.fromChat(s, chat, what.text);
  if (chat == null && where.text.trim().isNotEmpty) b['screen'] = where.text.trim();
  Bugs.add(s, b);
  Haptics.success();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bug caught (${s.list('bugs').where((x) => x['fixed'] != true).length} open). More → Bugs to send them.')));
  }
}

/// More → Bugs: every caught bug, copy them all for fixing, tick off the fixed ones.
class BugsPage extends StatelessWidget {
  const BugsPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final tt = Theme.of(context).textTheme;
          final scheme = Theme.of(context).colorScheme;
          final all = store.list('bugs').reversed.toList();
          final open = all.where((b) => b['fixed'] != true).length;
          return Scaffold(
            appBar: AppBar(title: const Text('Bugs')),
            floatingActionButton: FloatingActionButton.extended(
              icon: const Icon(Icons.bug_report_outlined),
              label: const Text('Catch a bug'),
              onPressed: () => catchBug(context, store),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              children: [
                Text(
                  'Type "bug: what went wrong" in the chat right after a wrong answer, or hold the answer → Catch a bug. '
                  'Then copy them all and send them in one go.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.copy),
                  label: Text('Copy $open open bug${open == 1 ? '' : 's'} to send'),
                  onPressed: open == 0
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: Bugs.report(store.list('bugs'))));
                          Haptics.success();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied. Paste it to Claude.')));
                          }
                        },
                ),
                const SizedBox(height: 12),
                if (all.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No bugs caught yet.', style: TextStyle(color: scheme.onSurfaceVariant))),
                  ),
                for (final b in all)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: CheckboxListTile(
                      value: b['fixed'] == true,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) => store.updateRec('bugs', b, v == true ? 'Bug fixed: ${b['note']}' : 'Bug open again: ${b['note']}',
                          (x) => x['fixed'] = v == true),
                      title: Text('${b['note']}',
                          style: b['fixed'] == true ? tt.bodyLarge?.copyWith(decoration: TextDecoration.lineThrough, color: scheme.onSurfaceVariant) : null),
                      subtitle: Text([
                        '${b['screen'] ?? 'App'} · ${niceWhen(b['at'] as int)}',
                        if (b['said'] != null) 'You: ${b['said']}',
                      ].join('\n'), maxLines: 3, overflow: TextOverflow.ellipsis),
                      secondary: IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => store.removeRec('bugs', b, 'Deleted bug: ${b['note']}'),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
}
