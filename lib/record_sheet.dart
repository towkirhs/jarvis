import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'haptics.dart';
import 'store.dart';

/// One field of a record that can be edited: text, longer text, a number, or a moment (date and time).
class Field {
  const Field(this.key, this.label, {this.kind = 'text', this.optional = false});
  final String key;
  final String label;

  /// text, long, number or when (milliseconds).
  final String kind;

  /// May be left empty (saved as null).
  final bool optional;
}

/// The same sheet for any record that has no editor of its own (promises, decisions, Your day entries):
/// change its fields, copy it as text, or delete it. Every change has Undo in Activity.
Future<void> showRecordSheet(
  BuildContext context,
  Store s,
  String col,
  Rec r, {
  required String title,
  required List<Field> fields,
  required String Function(Rec r) name,
}) {
  final ctrls = {
    for (final f in fields)
      if (f.kind != 'when') f.key: TextEditingController(text: r[f.key] == null ? '' : '${r[f.key]}'),
  };
  final when = <String, int?>{
    for (final f in fields)
      if (f.kind == 'when') f.key: r[f.key] as int?,
  };
  String? note;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final tt = Theme.of(ctx).textTheme;
      final scheme = Theme.of(ctx).colorScheme;

      Future<void> pickWhen(Field f) async {
        final now = DateTime.now();
        final start = when[f.key] == null ? now : fromMs(when[f.key]!);
        final d = await showDatePicker(context: ctx, initialDate: start, firstDate: DateTime(now.year - 10), lastDate: DateTime(now.year + 10));
        if (d == null || !ctx.mounted) return;
        final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(start));
        if (t == null) return;
        setS(() => when[f.key] = DateTime(d.year, d.month, d.day, t.hour, t.minute).millisecondsSinceEpoch);
      }

      String asText() => [
            for (final f in fields)
              if (f.kind == 'when' ? when[f.key] != null : ctrls[f.key]!.text.trim().isNotEmpty)
                '${f.label}: ${f.kind == 'when' ? niceWhen(when[f.key]!) : ctrls[f.key]!.text.trim()}',
          ].join('\n');

      Future<void> save() async {
        final values = <String, dynamic>{};
        for (final f in fields) {
          if (f.kind == 'when') {
            if (when[f.key] == null && !f.optional) return setS(() => note = '${f.label} is needed.');
            values[f.key] = when[f.key];
            continue;
          }
          final v = ctrls[f.key]!.text.trim();
          if (v.isEmpty && !f.optional) return setS(() => note = '${f.label} is needed.');
          if (f.kind == 'number') {
            final n = num.tryParse(v.replaceAll(',', ''));
            if (v.isNotEmpty && n == null) return setS(() => note = '${f.label}: a number, please.');
            values[f.key] = n;
          } else {
            values[f.key] = v.isEmpty ? null : v;
          }
        }
        await s.updateRec(col, r, 'Changed: ${name({...r, ...values})}', (x) => x.addAll(values));
        Haptics.success();
        if (ctx.mounted) Navigator.pop(ctx);
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: tt.headlineSmall),
            const SizedBox(height: 12),
            for (final f in fields) ...[
              if (f.kind == 'when')
                Card(
                  margin: EdgeInsets.zero,
                  color: scheme.surfaceContainerHighest,
                  child: ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: Text(f.label),
                    subtitle: Text(when[f.key] == null ? 'Not set' : niceWhen(when[f.key]!)),
                    trailing: when[f.key] != null && f.optional
                        ? IconButton(tooltip: 'Clear', icon: const Icon(Icons.close), onPressed: () => setS(() => when[f.key] = null))
                        : null,
                    onTap: () => pickWhen(f),
                  ),
                )
              else
                TextField(
                  controller: ctrls[f.key],
                  minLines: 1,
                  maxLines: f.kind == 'long' ? 6 : 1,
                  keyboardType: f.kind == 'number' ? TextInputType.number : TextInputType.text,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: f.optional ? '${f.label} (optional)' : f.label),
                ),
              const SizedBox(height: 12),
            ],
            if (note != null) ...[
              Text(note!, style: TextStyle(color: scheme.error)),
              const SizedBox(height: 8),
            ],
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
                onPressed: () {
                  Haptics.warn();
                  s.removeRec(col, r, 'Deleted: ${name(r)}');
                  Navigator.pop(ctx);
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: asText()));
                  Haptics.tap();
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Copied.')));
                  }
                },
              ),
              FilledButton(onPressed: save, child: const Text('Save')),
            ]),
          ]),
        ),
      );
    }),
  );
}
