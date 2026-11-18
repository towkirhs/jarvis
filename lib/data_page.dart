import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'backups.dart';
import 'haptics.dart';
import 'sections.dart';
import 'store.dart';

/// More → Move data: copy or save any one part of Jarvis, and add a copied part to this Jarvis.
class DataPage extends StatelessWidget {
  const DataPage({super.key, required this.store});
  final Store store;

  void _say(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _section(BuildContext context, Section sec) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(sec.name, style: Theme.of(ctx).textTheme.titleMedium)),
          ListTile(leading: const Icon(Icons.copy), title: const Text('Copy as text'), onTap: () => Navigator.pop(ctx, 'copy')),
          if (!kIsWeb)
            ListTile(leading: const Icon(Icons.save_alt), title: const Text('Save as a file'), onTap: () => Navigator.pop(ctx, 'save')),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;
    final text = store.exportSection(sec);
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) _say(context, '${sec.name} copied.');
    } else {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ${sec.name}',
        fileName: 'jarvis-${sec.key}-${DayStart.today()}.json',
        bytes: utf8.encode(text),
      );
      if (path != null && context.mounted) _say(context, '${sec.name} saved.');
    }
  }

  Future<void> _add(BuildContext context, String? text) async {
    if (text == null || text.trim().isEmpty) return;
    final Section sec;
    final int n;
    try {
      sec = Sections.parse(text).$1;
      n = Sections.parse(text).$2.values.fold(0, (a, l) => a + l.length);
    } catch (_) {
      if (context.mounted) _say(context, 'That is not a copied Jarvis section.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add ${sec.name}?'),
        content: Text('$n records. They are added next to what is here; ones already here are skipped. Undo in Activity takes them out again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    final (_, added) = await store.importSection(text);
    Haptics.success();
    if (context.mounted) _say(context, added == 0 ? 'Nothing new: all of it is already here.' : 'Added $added to ${sec.name}.');
  }

  Future<String?> _paste(BuildContext context) async {
    final ctrl = TextEditingController(text: (await Clipboard.getData('text/plain'))?.text ?? '');
    if (!context.mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste a section'),
        content: TextField(controller: ctrl, maxLines: 6, decoration: const InputDecoration(hintText: 'The copied text')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Next')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Move data')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Text('Take one part out', style: tt.titleMedium),
            const SizedBox(height: 4),
            Text('Copy or save just that part, to keep it, share it, or add it to Jarvis on another phone.',
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Column(children: [
                for (final sec in Sections.all)
                  ListTile(
                    title: Text(sec.name),
                    trailing: Text('${store.sectionCount(sec)}', style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    onTap: () => _section(context, sec),
                  ),
              ]),
            ),
            const SizedBox(height: 24),
            Text('Put one part in', style: tt.titleMedium),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Column(children: [
                if (!kIsWeb)
                  ListTile(
                    leading: const Icon(Icons.file_open_outlined),
                    title: const Text('Add from a file'),
                    onTap: () async => _add(context, await Backups.pick()),
                  ),
                ListTile(
                  leading: const Icon(Icons.content_paste),
                  title: const Text('Add from copied text'),
                  onTap: () async => _add(context, await _paste(context)),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
