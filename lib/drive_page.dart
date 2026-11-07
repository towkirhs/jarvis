import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'drive.dart';
import 'haptics.dart';
import 'store.dart';

/// Your Drive files as Jarvis's memory: connect, pick folders, mark some private, ask questions.
class DrivePage extends StatefulWidget {
  const DrivePage({super.key, required this.store});
  final Store store;

  @override
  State<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<DrivePage> {
  final _question = TextEditingController();
  late final _clientId = TextEditingController(text: s.local('google_web_client'));
  bool _busy = false;
  String? _status;
  DriveAnswer? _answer;
  int _files = 0;

  Store get s => widget.store;

  @override
  void initState() {
    super.initState();
    if (Drive.supported) Drive.index().then((f) => mounted ? setState(() => _files = f.length) : null);
  }

  @override
  void dispose() {
    _question.dispose();
    _clientId.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await job();
    } catch (e) {
      _status = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _addFolder() async {
    final picked = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => _FolderPicker(store: s)),
    );
    if (picked == null) return;
    final f = Drive.folders(s);
    if (f.any((x) => x['id'] == picked['id'])) return;
    f.add({'id': picked['id'], 'name': picked['name'], 'private': false});
    await Drive.setFolders(s, f);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (!Drive.supported) {
      return Scaffold(
        appBar: AppBar(title: const Text('Google Drive')),
        body: const Padding(padding: EdgeInsets.all(24), child: Text('Drive works in the Android app only.')),
      );
    }
    final email = s.local('drive_email');
    final folders = Drive.folders(s);
    final updated = int.tryParse(s.local('drive_updated') ?? '');
    return Scaffold(
      appBar: AppBar(title: const Text('Google Drive')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          if (email == null) ...[
            Text('Connect your Drive', style: tt.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Jarvis only reads, and only the folders you pick. What it reads is kept on this phone.',
              style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            const _SetupSteps(),
            const SizedBox(height: 16),
            TextField(
              controller: _clientId,
              decoration: const InputDecoration(labelText: 'Web client ID (ends in .apps.googleusercontent.com)'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        await s.setLocal('google_web_client', _clientId.text.trim());
                        final who = await Drive.connect(s);
                        Haptics.success();
                        _status = 'Connected as $who.';
                      }),
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google'),
            ),
          ] else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cloud_done_outlined),
              title: Text(email),
              subtitle: Text(updated == null
                  ? '$_files files read'
                  : '$_files files read, updated ${niceWhen(updated)}'),
              trailing: TextButton(
                onPressed: () => _run(() async {
                  await Drive.disconnect(s);
                  await Drive.clearIndex();
                  _files = 0;
                  _status = 'Disconnected. What Jarvis read was deleted from this phone.';
                }),
                child: const Text('Disconnect'),
              ),
            ),
            Text('Folders', style: tt.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Private folders are searched on this phone only. Their text is never sent to the AI. '
              'PDFs in private folders cannot be read yet, because reading a PDF needs the AI.',
              style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            for (final f in folders)
              Card(
                child: ListTile(
                  leading: Icon(f['private'] == true ? Icons.lock_outline : Icons.folder_outlined),
                  title: Text(f['name'] as String),
                  subtitle: Text(f['private'] == true ? 'Private: phone only' : 'Can be sent to the AI'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(
                      value: f['private'] == true,
                      onChanged: (v) async {
                        f['private'] = v;
                        await Drive.setFolders(s, folders);
                        setState(() {});
                      },
                    ),
                    IconButton(
                      tooltip: 'Remove folder',
                      icon: const Icon(Icons.close),
                      onPressed: () async {
                        folders.remove(f);
                        await Drive.setFolders(s, folders);
                        setState(() {});
                      },
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(_addFolder),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Add folder'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy || folders.isEmpty
                      ? null
                      : () => _run(() async {
                            final summary = await Drive.update(s, (line) {
                              if (mounted) setState(() => _status = line);
                            });
                            _files = (await Drive.index()).length;
                            Haptics.success();
                            _status = summary;
                          }),
                  icon: const Icon(Icons.sync),
                  label: const Text('Read files'),
                ),
              ),
            ]),
            const SizedBox(height: 24),
            Text('Ask your files', style: tt.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _question,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _ask(),
              decoration: InputDecoration(
                hintText: 'What does my rent agreement say about notice?',
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _ask),
              ),
            ),
          ],
          if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
          if (_status != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_status!)),
          if (_answer != null) ..._answerView(context, _answer!),
        ],
      ),
    );
  }

  void _ask() {
    final q = _question.text.trim();
    if (q.isEmpty || _busy) return;
    _run(() async {
      final a = await Drive.ask(s, q);
      _answer = a;
      if (a.passages.isEmpty) _status = 'Nothing in your files matches that.';
    });
  }

  List<Widget> _answerView(BuildContext context, DriveAnswer a) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final shared = a.passages.where((p) => !p.private).toList();
    return [
      if (a.answer != null)
        Card(
          color: scheme.primaryContainer.withValues(alpha: 0.6),
          margin: const EdgeInsets.only(top: 16),
          child: Padding(padding: const EdgeInsets.all(16), child: SelectableText(a.answer!, style: tt.bodyLarge)),
        ),
      for (final p in a.passages)
        Card(
          child: ExpansionTile(
            leading: Icon(p.private ? Icons.lock_outline : Icons.description_outlined),
            title: Text(p.private ? p.file : '[${shared.indexOf(p) + 1}] ${p.file}'),
            subtitle: Text(p.private ? '${p.folder}, private: not sent to the AI' : p.folder),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [SelectableText(p.text)],
          ),
        ),
    ];
  }
}

/// How to register Jarvis with Google, with this app's exact values to copy.
class _SetupSteps extends StatelessWidget {
  const _SetupSteps();

  static const package = 'com.towkirhs.jarcis';
  static const sha1 = 'E0:30:B5:BB:C0:C5:A6:3B:14:40:89:2C:7C:AE:03:6E:34:B6:37:4E';

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    Widget copy(String label, String value) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          subtitle: SelectableText(value),
          trailing: IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied $label')));
            },
          ),
        );
    const steps = [
      'Open console.cloud.google.com, create a project, and turn on the Google Drive API.',
      'OAuth consent screen: choose External, fill in the app name and your email, add the scope '
          '".../auth/drive.readonly", and add your own Gmail as a test user. Leave it in Testing.',
      'Credentials, Create OAuth client ID, Android: use the package name and SHA-1 below.',
      'Credentials, Create OAuth client ID, Web application (no settings needed). Copy its client ID and paste it below.',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('One-time setup (about 10 minutes)', style: tt.titleSmall),
          const SizedBox(height: 8),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('${i + 1}. ${steps[i]}'),
            ),
          copy('Package name', package),
          copy('SHA-1', sha1),
        ]),
      ),
    );
  }
}

/// Browse your Drive folders and pick one.
class _FolderPicker extends StatefulWidget {
  const _FolderPicker({required this.store});
  final Store store;

  @override
  State<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<_FolderPicker> {
  final _path = <Map<String, dynamic>>[
    {'id': 'root', 'name': 'My Drive'},
  ];
  Future<List<Map<String, dynamic>>>? _children;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() =>
      _children = Drive.list(widget.store, _path.last['id'] as String, foldersOnly: true, interactive: true);

  @override
  Widget build(BuildContext context) {
    final here = _path.last;
    return Scaffold(
      appBar: AppBar(
        title: Text(here['name'] as String),
        leading: _path.length > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _path.removeLast();
                  _load();
                }),
              )
            : null,
      ),
      floatingActionButton: here['id'] == 'root'
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.pop(context, here),
              icon: const Icon(Icons.check),
              label: const Text('Use this folder'),
            ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _children,
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(padding: const EdgeInsets.all(24), child: Text('${snap.error}'.replaceFirst('Exception: ', '')));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          if (items.isEmpty) return const Center(child: Text('No folders inside. Use this folder, or go back.'));
          return ListView(children: [
            for (final f in items)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(f['name'] as String),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(() {
                  _path.add(f);
                  _load();
                }),
              ),
          ]);
        },
      ),
    );
  }
}
