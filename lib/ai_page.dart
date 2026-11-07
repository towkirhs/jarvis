import 'package:flutter/material.dart';

import 'ai.dart';
import 'haptics.dart';
import 'store.dart';

/// Choose where Jarvis thinks, and in what order: phone rules, your server, hosted APIs.
class AiPage extends StatefulWidget {
  const AiPage({super.key, required this.store});
  final Store store;

  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  Store get s => widget.store;
  late List<Map<String, dynamic>> _list = AI.providers(s);
  final _testing = <String, String>{};

  void _save() {
    AI.save(s, _list);
    setState(() => _list = AI.providers(s));
  }

  String _describe(Map<String, dynamic> p) => switch (p['type']) {
        'phone' => 'Rules on this phone, no AI: alarms, timed tasks, money, habits, quick questions. Offline and instant.',
        'gemini' => s.apiKey.isEmpty ? 'Add your Gemini key in Settings to use this.' : 'Model ${s.settings['model'] ?? 'gemini-2.5-flash-lite'}',
        _ => '${p['model'] ?? '?'} at ${p['url'] ?? '?'}',
      };

  IconData _icon(Map<String, dynamic> p) => switch (p['type']) {
        'phone' => Icons.phone_android,
        'gemini' => Icons.auto_awesome,
        _ => p['kind'] == 'server' ? Icons.dns_outlined : Icons.cloud_outlined,
      };

  Future<void> _edit(Map<String, dynamic>? p, {String kind = 'server'}) async {
    final isNew = p == null;
    final entry = p ?? {'id': 'ai${DateTime.now().millisecondsSinceEpoch}', 'type': 'openai', 'kind': kind, 'on': true};
    final server = (entry['kind'] ?? kind) == 'server';
    final name = TextEditingController(text: (entry['name'] as String?) ?? (server ? 'My server' : 'Hosted API'));
    final url = TextEditingController(
        text: (entry['url'] as String?) ?? (server ? 'https://my-server.your-tailnet.ts.net/v1' : 'https://openrouter.ai/api/v1'));
    final model = TextEditingController(text: (entry['model'] as String?) ?? (server ? 'gemma4:12b' : ''));
    final key = TextEditingController(text: s.local('ai_key_${entry['id']}') ?? '');
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(isNew ? (server ? 'Add your server' : 'Add an API') : 'Edit ${entry['name']}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 12),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Address (https, OpenAI-style, ends in /v1)',
                  helperText: 'Android only allows https. For your server, Tailscale gives you an https address.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 12),
              TextField(controller: model, decoration: const InputDecoration(labelText: 'Model, like gemma4:12b or qwen3.5:9b')),
              const SizedBox(height: 12),
              TextField(
                controller: key,
                obscureText: true,
                decoration: InputDecoration(labelText: 'API key (optional for your own server)', errorText: error),
              ),
            ]),
          ),
          actions: [
            if (!isNew)
              TextButton(
                onPressed: () {
                  Haptics.warn();
                  _list.removeWhere((x) => x['id'] == entry['id']);
                  s.setLocal('ai_key_${entry['id']}', null);
                  Navigator.pop(ctx, true);
                },
                child: const Text('Remove'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final u = url.text.trim();
                if (u.isEmpty || model.text.trim().isEmpty) {
                  return setD(() => error = Haptics.rejected() ?? 'Fill in the address and the model.');
                }
                if (!u.startsWith('https://')) {
                  return setD(() => error = Haptics.rejected() ?? 'The address must start with https://');
                }
                entry
                  ..['name'] = name.text.trim().isEmpty ? 'AI' : name.text.trim()
                  ..['url'] = u
                  ..['model'] = model.text.trim();
                s.setLocal('ai_key_${entry['id']}', key.text.trim().isEmpty ? null : key.text.trim());
                if (isNew) _list.add(entry);
                Haptics.tap();
                Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) _save();
  }

  Future<void> _test(Map<String, dynamic> p) async {
    setState(() => _testing[p['id'] as String] = 'Testing…');
    String result;
    try {
      result = await AI.test(s, p);
      Haptics.success();
    } catch (e) {
      Haptics.reject();
      result = 'Failed: ${e.toString().replaceFirst('Exception: ', '')}';
    }
    if (mounted) setState(() => _testing[p['id'] as String] = result);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI models')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Jarvis tries these from the top. If one is off, not set up or fails, it goes to the next. '
            'Hold the number to drag. When phone rules come first, simple notes never leave the phone.',
            style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderStart: (_) => Haptics.dragStart(),
            onReorderEnd: (_) => Haptics.dragEnd(),
            onReorder: (from, to) {
              if (to > from) to--;
              _list.insert(to, _list.removeAt(from));
              _save();
            },
            children: [
              for (var i = 0; i < _list.length; i++)
                Card(
                  key: ValueKey(_list[i]['id']),
                  child: Column(children: [
                    ListTile(
                      leading: ReorderableDelayedDragStartListener(
                        index: i,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('${i + 1}', style: tt.titleMedium),
                          const SizedBox(width: 8),
                          Icon(_icon(_list[i])),
                        ]),
                      ),
                      title: Text(_list[i]['name'] as String),
                      subtitle: Text(_testing[_list[i]['id']] ?? _describe(_list[i])),
                      trailing: Switch(
                        value: _list[i]['on'] == true,
                        onChanged: (v) {
                          Haptics.toggle(v);
                          _list[i]['on'] = v;
                          _save();
                        },
                      ),
                      onTap: _list[i]['type'] == 'openai' ? () => _edit(_list[i]) : null,
                    ),
                    if (_list[i]['type'] != 'phone')
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8, bottom: 4),
                          child: TextButton(onPressed: () => _test(_list[i]), child: const Text('Test')),
                        ),
                      ),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _edit(null, kind: 'server'),
                icon: const Icon(Icons.dns_outlined),
                label: const Text('Add your server'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _edit(null, kind: 'api'),
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('Add an API'),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          Text('Your own server', style: tt.titleSmall),
          const SizedBox(height: 8),
          Text(
            'Recommended: Gemma 4 12B (4-bit) on a 12–16 GB GPU, Qwen 3.5 9B on 8 GB, or Gemma 4 26B A4B on a '
            'server without a GPU (slower). Run it with Ollama, then put the server and phone on Tailscale and '
            'run "tailscale serve --bg 11434" on the server: it gives an https address only your devices can '
            'reach. Use that address plus /v1 here.',
            style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
