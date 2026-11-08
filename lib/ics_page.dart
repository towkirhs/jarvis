import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'clash.dart';
import 'ics.dart';
import 'store.dart';

/// Move a calendar in or out as a .ics file: Google, Apple, Outlook and most others read and write them.
class IcsPage extends StatefulWidget {
  const IcsPage({super.key, required this.store});
  final Store store;

  @override
  State<IcsPage> createState() => _IcsPageState();
}

class _IcsPageState extends State<IcsPage> {
  Store get s => widget.store;
  bool _busy = false;

  void _say(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _export() async {
    final items = s.list('items');
    final count = items.where((i) => (i['kind'] == 'event' || i['kind'] == 'task') && i['when'] is int && i['status'] != 'cancelled').length;
    if (count == 0) return _say('Nothing with a date to export yet.');
    setState(() => _busy = true);
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save calendar',
        fileName: 'jarvis-calendar.ics',
        bytes: Uint8List.fromList(utf8.encode(Ics.export(items))),
      );
      if (!mounted) return;
      if (kIsWeb || path != null) _say('Saved $count items.');
    } catch (e) {
      if (mounted) _say('Could not save: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['ics'], withData: true);
      final bytes = picked?.files.single.bytes;
      if (bytes == null) return;
      final found = Ics.parse(utf8.decode(bytes, allowMalformed: true));
      final plan = plan(found);
      if (!mounted) return;
      if (plan.add.isEmpty) {
        _say(found.isEmpty ? 'No events found in that file.' : 'Nothing new: ${plan.skipped} already here or in the past.');
        return;
      }
      final approx = plan.add.where((e) => e.approx).length;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Add ${plan.add.length} items?'),
          content: Text([
            '${plan.skipped} skipped (past, or already in Jarvis).',
            if (approx > 0) '$approx repeat in a way Jarvis cannot follow, so only their next time is added.',
            'Times with a named time zone are read as your local time.',
          ].join('\n')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      );
      if (ok != true) return;
      final undo = <Rec>[];
      for (final e in plan.add) {
        final when = e.allDay ? DateTime(e.start.year, e.start.month, e.start.day, 9) : e.start;
        var ms = when.millisecondsSinceEpoch;
        if (e.repeat != null && ms < DateTime.now().millisecondsSinceEpoch) ms = Store.nextRepeat(ms, e.repeat!);
        await s.addItem(
          kind: e.todo ? 'task' : 'event',
          title: e.title,
          when: ms,
          undo: undo,
          extra: {
            'desc': e.desc,
            'allDay': e.allDay,
            'repeat': e.repeat,
            'dur': e.minutes,
            'tags': e.tags,
            'uid': e.uid,
            'lead': e.todo ? 0 : (e.lead ?? 0),
          },
        );
      }
      s.logAction('Imported ${plan.add.length} from a calendar file', undo);
      s.save();
      if (mounted) _say('Added ${plan.add.length} items. Undo is in the activity log.');
    } catch (e) {
      if (mounted) _say('Could not read that file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Which of the file's items to add: not in the past (unless they repeat), not already here, at most 500.
  ({List<IcsEvent> add, int skipped}) plan(List<IcsEvent> found) {
    final now = DateTime.now();
    final have = s.list('items');
    final uids = {for (final i in have) if (i['uid'] != null) i['uid']};
    final keys = {for (final i in have) '${i['title']}|${i['when']}'};
    final add = <IcsEvent>[];
    var skipped = 0;
    for (final e in found) {
      final at = e.allDay ? DateTime(e.start.year, e.start.month, e.start.day, 9) : e.start;
      final past = !at.isAfter(now) && e.repeat == null;
      final dup = (e.uid != null && uids.contains(e.uid)) || keys.contains('${e.title}|${at.millisecondsSinceEpoch}');
      if (past || dup || add.length >= 500) {
        skipped++;
        continue;
      }
      add.add(e);
    }
    return (add: add, skipped: skipped);
  }

  @override
  Widget build(BuildContext context) {
    final events = s.list('items').where((i) => i['kind'] == 'event' && i['status'] == 'open').length;
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar file')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'A .ics file is the common language of calendars. Export to back up or open Jarvis events in Google, Apple or Outlook calendar; import to bring theirs in.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('Export my calendar'),
              subtitle: Text('$events open events, and tasks with a date'),
              onTap: _busy ? null : _export,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Import a calendar file'),
              subtitle: const Text('Past events and ones already here are skipped. You can undo it.'),
              onTap: _busy ? null : _import,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A repeating event shows only its next time. Reminders before an event (${Lead.name(Lead.defaultFor(s.settings))} by default) come along both ways.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
