import 'package:flutter/material.dart';

import 'ai.dart';
import 'brain.dart';
import 'haptics.dart';
import 'offline_llm.dart';
import 'store.dart';
import 'web.dart';

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
  String? _installed;
  String? _downloading;
  int _progress = 0;
  String? _offlineError;

  @override
  void initState() {
    super.initState();
    if (OfflineLlm.supported) OfflineLlm.installed().then((id) => mounted ? setState(() => _installed = id) : null);
  }

  Future<void> _download(OfflineModel m) async {
    setState(() {
      _downloading = m.id;
      _progress = 0;
      _offlineError = null;
    });
    try {
      await OfflineLlm.download(m.id, (p) {
        if (mounted) setState(() => _progress = p);
      });
      await AI.checkOffline();
      // Put it in the order right after the phone rules, switched on.
      if (!_list.any((p) => p['type'] == 'offline')) {
        final at = _list.indexWhere((p) => p['type'] == 'phone') + 1;
        _list.insert(at, {'id': 'offline', 'type': 'offline', 'name': 'Offline model', 'on': true});
      }
      _save();
      Haptics.success();
      _installed = m.id;
    } catch (e) {
      Haptics.reject();
      _offlineError = 'Download failed: ${e.toString().replaceFirst('Exception: ', '')}';
    }
    if (mounted) setState(() => _downloading = null);
  }

  Future<void> _removeOffline() async {
    Haptics.warn();
    await OfflineLlm.remove();
    await AI.checkOffline();
    _list.removeWhere((p) => p['type'] == 'offline');
    _save();
    setState(() => _installed = null);
  }

  void _save() {
    AI.save(s, _list);
    setState(() => _list = AI.providers(s));
  }

  String _describe(Map<String, dynamic> p) => switch (p['type']) {
        'phone' => 'Rules on this phone, no AI: alarms, timed tasks, money, habits, quick questions. Offline and instant.',
        'offline' => AI.offlineReady
            ? '${OfflineLlm.models.firstWhere((m) => m.id == _installed, orElse: () => OfflineLlm.models.first).name}, on this phone, no internet'
            : 'Download a model below.',
        'gemini' => s.apiKey.isEmpty ? 'Tap to add your Gemini key' : 'Model ${s.settings['model'] ?? 'gemini-2.5-flash-lite'}',
        _ => '${p['model'] ?? '?'} at ${p['url'] ?? '?'}',
      };

  IconData _icon(Map<String, dynamic> p) => switch (p['type']) {
        'phone' => Icons.phone_android,
        'offline' => Icons.download_done,
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

  /// Your Gemini key and model, kept on this phone only.
  Future<void> _editGemini() async {
    final key = TextEditingController(text: s.apiKey);
    final model = TextEditingController(text: (s.settings['model'] as String?) ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Google Gemini'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: key,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API key',
                helperText: 'Free at aistudio.google.com. Stays on this phone, never in backups or sync.',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: model,
              decoration: const InputDecoration(
                labelText: 'Model',
                hintText: 'gemini-2.5-flash-lite',
                helperText: 'Leave empty for the default.',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    await s.setApiKey(key.text);
    s.settings['model'] = model.text.trim().isEmpty ? 'gemini-2.5-flash-lite' : model.text.trim();
    _save();
    Haptics.tap();
    // Notes that waited for an AI can go now.
    await Brain.drain(s);
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
                      onTap: switch (_list[i]['type']) {
                        'openai' => () => _edit(_list[i]),
                        'gemini' => _editGemini,
                        _ => null,
                      },
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
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.public),
            title: const Text('Search the web when needed'),
            subtitle: Text(Web.available(s)
                ? 'For news, weather, prices and facts your notes cannot answer. Only the search words leave the phone. '
                    '"search for …" always searches.'
                : 'Needs Google Gemini or a Groq API (gpt-oss models) above.'),
            value: Web.on(s),
            onChanged: (v) {
              Haptics.toggle(v);
              s.settings['web'] = v;
              s.save();
              setState(() {});
            },
          ),
          if (OfflineLlm.supported) ...[
            const SizedBox(height: 24),
            Text('Offline models', style: tt.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Download once and Jarvis thinks on the phone, with no internet and nothing leaving it. '
              'Slower than a server or Gemini, and uses battery while it works. One model at a time.',
              style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            for (final m in OfflineLlm.models)
              Card(
                child: ListTile(
                  title: Text('${m.name}, ${m.size}'),
                  subtitle: _downloading == m.id
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(value: _progress / 100),
                        )
                      : Text(m.about),
                  trailing: _installed == m.id
                      ? TextButton(onPressed: _removeOffline, child: const Text('Delete'))
                      : (_downloading == m.id
                          ? Text('$_progress%')
                          : TextButton(
                              onPressed: _downloading == null ? () => _download(m) : null,
                              child: Text(_installed == null ? 'Download' : 'Switch'),
                            )),
                ),
              ),
            if (_offlineError != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(_offlineError!, style: TextStyle(color: scheme.error))),
            Text('Download on Wi-Fi and keep this screen open until it finishes.',
                style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
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
