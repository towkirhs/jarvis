import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brain.dart';
import 'haptics.dart';
import 'memory.dart';
import 'store.dart';

/// Everything Jarvis remembers about you: see it, correct it, pin what matters, delete what is wrong.
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key, required this.store});
  final Store store;

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  Store get s => widget.store;

  Future<String?> _ask(String title, String initial, {bool canDelete = false}) async {
    final ctrl = TextEditingController(text: initial);
    final out = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: Memory.maxText,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'For example: Supports Manchester United'),
        ),
        actions: [
          if (canDelete)
            TextButton(onPressed: () => Navigator.pop(ctx, '\u0000delete'), child: const Text('Forget')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    ctrl.dispose();
    return out;
  }

  Future<void> _add() async {
    final t = await _ask('Remember something', '');
    if (t == null) return;
    final fact = Memory.clean(t);
    if (fact == null) return;
    Memory.merge(s.list('memories'), [fact], now: DateTime.now().millisecondsSinceEpoch, nextId: s.nextId);
    s.save();
    setState(() {});
  }

  Future<void> _edit(Rec m) async {
    final t = await _ask('Edit', m['text'] as String, canDelete: true);
    if (t == null) return;
    if (t == '\u0000delete') {
      s.list('memories').remove(m);
    } else {
      final fact = Memory.clean(t);
      if (fact == null) return;
      m['text'] = fact;
    }
    s.save();
    setState(() {});
  }

  Future<void> _forgetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forget everything?'),
        content: const Text('Jarvis will start again knowing nothing about you. Your tasks, notes and journal stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Forget all')),
        ],
      ),
    );
    if (ok != true) return;
    s.list('memories').clear();
    s.save();
    setState(() {});
  }

  /// "Seen 5 times, last today".
  String _seen(Rec m) {
    final n = (m['n'] as int?) ?? 1;
    final ms = (m['last'] as int?) ?? 0;
    final day = dayKey(fromMs(ms)) == dayKey(DateTime.now()) ? 'today' : niceDay(ms).toLowerCase();
    return n <= 1 ? 'Noted $day' : 'Came up $n times, last $day';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = [...s.list('memories')]..sort((a, b) {
        final pin = ((b['pin'] == true) ? 1 : 0) - ((a['pin'] == true) ? 1 : 0);
        if (pin != 0) return pin;
        final n = ((b['n'] as int?) ?? 1).compareTo((a['n'] as int?) ?? 1);
        return n != 0 ? n : ((b['last'] as int?) ?? 0).compareTo((a['last'] as int?) ?? 0);
      });
    final on = s.settings['memory'] != false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory'),
        actions: [
          IconButton(
            tooltip: 'Copy context for ChatGPT',
            icon: const Icon(Icons.content_copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: Brain.chatgptContext(s)));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied. Paste it into your ChatGPT Project chat.')),
              );
            },
          ),
          if (all.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (_) => _forgetAll(),
              itemBuilder: (_) => const [PopupMenuItem(value: 'all', child: Text('Forget everything'))],
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Remember'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: [
          Card(
            child: SwitchListTile(
              title: const Text('Learn from my notes'),
              subtitle: const Text('Jarvis saves lasting facts it hears, like your team, your people and your routines'),
              value: on,
              onChanged: (v) {
                Haptics.toggle(v);
                s.settings['memory'] = v;
                s.save();
                setState(() {});
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Text(
              'The facts that fit your note are sent to the AI you use, along with the rest of what Jarvis knows, so any '
              'model understands you. They stay on your phone otherwise, and are encrypted when you sync.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          if (all.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                on
                    ? 'Nothing yet. As you talk to Jarvis, the things you keep mentioning will show up here. You can also tap Remember.'
                    : 'Learning is off. Turn it on above, or tap Remember to add facts yourself.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final m in all)
                    ListTile(
                      title: Text(m['text'] as String),
                      subtitle: Text(_seen(m)),
                      onTap: () => _edit(m),
                      trailing: IconButton(
                        tooltip: m['pin'] == true ? 'Unpin' : 'Always remember',
                        icon: Icon(m['pin'] == true ? Icons.push_pin : Icons.push_pin_outlined),
                        color: m['pin'] == true ? scheme.primary : null,
                        onPressed: () {
                          m['pin'] = m['pin'] != true;
                          s.save();
                          setState(() {});
                        },
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
