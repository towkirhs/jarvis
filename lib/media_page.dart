import 'package:flutter/material.dart';

import 'haptics.dart';
import 'store.dart';

/// Movies, series and books: what you want to watch or read, what you are on now, and what you finished
/// (with a rating and a note). Collection `media` {title, kind: movie|series|book, status: want|now|done, rating, note, at, doneAt}.
class Media {
  static const kinds = {'movie': 'Movie', 'series': 'Series', 'book': 'Book'};
  static const statuses = {'now': 'Now', 'want': 'Want to', 'done': 'Finished'};

  static IconData icon(String? kind) => switch (kind) {
        'book' => Icons.menu_book_outlined,
        'series' => Icons.live_tv_outlined,
        _ => Icons.movie_outlined,
      };

  /// "Watching" or "Reading", by kind.
  static String verb(String? kind, String status) => switch (status) {
        'now' => kind == 'book' ? 'Reading' : 'Watching',
        'want' => kind == 'book' ? 'Want to read' : 'Want to watch',
        _ => kind == 'book' ? 'Read' : 'Watched',
      };
}

class MediaPage extends StatefulWidget {
  const MediaPage({super.key, required this.store});
  final Store store;

  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage> {
  String? _kind; // null = everything

  Store get s => widget.store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final tt = Theme.of(context).textTheme;
          final scheme = Theme.of(context).colorScheme;
          final all = s.list('media').where((m) => _kind == null || m['kind'] == _kind).toList()
            ..sort((a, b) => ((b['doneAt'] ?? b['at'] ?? 0) as int).compareTo((a['doneAt'] ?? a['at'] ?? 0) as int));
          Widget section(String status) {
            final list = all.where((m) => (m['status'] ?? 'want') == status).toList();
            if (list.isEmpty) return const SizedBox.shrink();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                child: Text('${Media.statuses[status]} · ${list.length}', style: tt.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              Card(
                margin: EdgeInsets.zero,
                child: Column(children: [
                  for (final m in list)
                    ListTile(
                      leading: Icon(Media.icon(m['kind'] as String?)),
                      title: Text('${m['title']}'),
                      subtitle: Text([
                        Media.verb(m['kind'] as String?, status),
                        if (m['rating'] is num) '★' * (m['rating'] as num).round(),
                        if ((m['note'] as String?)?.isNotEmpty ?? false) m['note'],
                      ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => _edit(m),
                    ),
                ]),
              ),
            ]);
          }

          return Scaffold(
            appBar: AppBar(title: const Text('Movies and books')),
            floatingActionButton: FloatingActionButton(tooltip: 'Add', onPressed: () => _edit(null), child: const Icon(Icons.add)),
            body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
              Wrap(spacing: 8, children: [
                ChoiceChip(label: const Text('All'), selected: _kind == null, onSelected: (_) => setState(() => _kind = null)),
                for (final k in Media.kinds.entries)
                  ChoiceChip(label: Text('${k.value}s'), selected: _kind == k.key, onSelected: (_) => setState(() => _kind = k.key)),
              ]),
              if (all.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Text('Nothing yet. Tap + or tell Jarvis "watched Inception, 4 stars".',
                      textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              section('now'),
              section('want'),
              section('done'),
            ]),
          );
        },
      );

  Future<void> _edit(Rec? m) async {
    final title = TextEditingController(text: m?['title'] as String? ?? '');
    final note = TextEditingController(text: m?['note'] as String? ?? '');
    var kind = m?['kind'] as String? ?? _kind ?? 'movie';
    var status = m?['status'] as String? ?? 'want';
    var rating = (m?['rating'] as num?)?.round() ?? 0;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(m == null ? 'Add' : 'Change', style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: 12),
              TextField(
                controller: title,
                autofocus: m == null,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                for (final k in Media.kinds.entries)
                  ChoiceChip(label: Text(k.value), selected: kind == k.key, onSelected: (_) => setS(() => kind = k.key)),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final st in Media.statuses.keys)
                  ChoiceChip(label: Text(Media.verb(kind, st)), selected: status == st, onSelected: (_) => setS(() => status = st)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    tooltip: '$i star${i == 1 ? '' : 's'}',
                    icon: Icon(i <= rating ? Icons.star : Icons.star_border),
                    onPressed: () => setS(() => rating = rating == i ? 0 : i),
                  ),
              ]),
              TextField(controller: note, maxLines: 3, minLines: 1, decoration: const InputDecoration(labelText: 'Note')),
              const SizedBox(height: 16),
              Row(children: [
                if (m != null)
                  TextButton(
                    onPressed: () {
                      s.removeRec('media', m, 'Deleted ${m['title']}');
                      Navigator.pop(ctx);
                    },
                    child: const Text('Delete'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    final t = title.text.trim();
                    if (t.isEmpty) return Haptics.reject();
                    final now = DateTime.now().millisecondsSinceEpoch;
                    void fill(Rec r) {
                      r['title'] = t;
                      r['kind'] = kind;
                      if (status == 'done' && r['status'] != 'done') r['doneAt'] = now;
                      r['status'] = status;
                      r['rating'] = rating == 0 ? null : rating;
                      r['note'] = note.text.trim().isEmpty ? null : note.text.trim();
                    }

                    if (m == null) {
                      final r = <String, dynamic>{'id': s.nextId(), 'at': now};
                      fill(r);
                      s.list('media').add(r);
                      s.logAction('Added $t', [{'op': 'rm', 'col': 'media', 'id': r['id']}]);
                      s.save();
                    } else {
                      await s.updateRec('media', m, 'Changed $t', fill);
                    }
                    Haptics.success();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
