import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'habit_core.dart';
import 'habit_stats.dart';
import 'habits_screen.dart' show HabitPage;
import 'haptics.dart';
import 'store.dart';

/// Icons a habit can have, by key.
const habitIcons = <String, IconData>{
  'check': Icons.check_circle_outline,
  'fitness': Icons.fitness_center,
  'run': Icons.directions_run,
  'walk': Icons.directions_walk,
  'water': Icons.water_drop_outlined,
  'book': Icons.menu_book_outlined,
  'study': Icons.school_outlined,
  'pray': Icons.self_improvement,
  'sleep': Icons.bedtime_outlined,
  'sun': Icons.wb_sunny_outlined,
  'food': Icons.restaurant_outlined,
  'phone': Icons.phone_android,
  'smoke': Icons.smoke_free,
  'money': Icons.savings_outlined,
  'code': Icons.code,
  'music': Icons.music_note_outlined,
  'clean': Icons.cleaning_services_outlined,
  'heart': Icons.favorite_border,
};

const typeIcons = <String, IconData>{
  'yesno': Icons.check_circle_outline,
  'count': Icons.exposure_plus_1,
  'duration': Icons.timer_outlined,
  'quantity': Icons.water_drop_outlined,
  'frequency': Icons.repeat,
  'percent': Icons.percent,
  'distance': Icons.straighten,
  'time': Icons.schedule,
  'rating': Icons.star_outline,
  'checklist': Icons.checklist,
  'limit': Icons.block,
  'auto': Icons.sensors,
};

IconData habitIcon(Rec h) => habitIcons[h['icon']] ?? typeIcons[h['type'] ?? 'yesno'] ?? Icons.check_circle_outline;

String fmtNum(num v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(v.abs() < 10 ? 2 : 1).replaceFirst(RegExp(r'0+$'), '');

String time12(String hhmm) {
  final p = hhmm.split(':');
  final h = int.parse(p[0]);
  return '${h % 12 == 0 ? 12 : h % 12}:${p[1]} ${h < 12 ? 'am' : 'pm'}';
}

/// One line on how a habit stands on a day: "15 of 20 push-ups", "Done at 5:50 am", "Rest day".
String habitDayText(Rec h, DateTime day) {
  final e = HabitCore.entry(h, dk(day));
  if (e?['skip'] == true) return 'Rest day';
  if (e?['miss'] == true) return 'Missed';
  final type = (h['type'] as String?) ?? 'yesno';
  final t = HabitCore.target(h, day);
  final unit = (h['unit'] as String?) ?? '';
  final v = e?['v'] as num?;
  switch (type) {
    case 'yesno':
    case 'auto':
      return HabitCore.done(h, day) ? 'Done' : 'Not yet';
    case 'time':
      final at = e?['at'] as String?;
      final by = h['by'] as String?;
      if (at == null) return by == null ? 'Not yet' : 'By ${time12(by)}';
      return '${HabitCore.done(h, day) ? 'Done' : 'Late'} at ${time12(at)}';
    case 'checklist':
      final total = ((h['items'] as List?) ?? const []).length;
      final n = ((e?['items'] as List?) ?? const []).where((x) => x == true).length;
      return '$n of $total steps';
    case 'rating':
      return v == null ? 'Not rated' : '${fmtNum(v)} of ${h['scale'] ?? 10}';
    case 'limit':
      return '${fmtNum(v ?? 0)} of max ${fmtNum(t ?? 0)} $unit'.trim();
    default:
      return '${fmtNum(v ?? 0)} of ${fmtNum(t ?? 0)} $unit'.trim();
  }
}

/// After a habit is done: haptics, and a nudge to the next habit in its stack.
void afterHabitChange(BuildContext context, Store s, Rec h, {bool wasDone = false}) {
  final now = DateTime.now();
  if (!wasDone && HabitCore.done(h, now)) {
    Haptics.success();
    final next = HabitCore.nextInStack(s.list('habits'), h, now);
    if (next != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Next: ${next['name']}'),
        action: SnackBarAction(label: 'Open', onPressed: () => showHabitDay(context, s, next, now)),
      ));
    }
  } else {
    Haptics.tap();
  }
}

/// The main one-tap control for a habit today, matched to how it is measured.
class HabitQuickControl extends StatefulWidget {
  const HabitQuickControl({super.key, required this.store, required this.habit});
  final Store store;
  final Rec habit;

  @override
  State<HabitQuickControl> createState() => _HabitQuickControlState();
}

class _HabitQuickControlState extends State<HabitQuickControl> {
  Timer? _tick;

  Rec get h => widget.habit;
  Store get s => widget.store;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(HabitQuickControl old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  void _syncTicker() {
    final running = h['timer'] != null;
    if (running && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
    } else if (!running) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _do(Future<void> Function() change) async {
    final was = HabitCore.done(h, DateTime.now());
    await change();
    if (mounted) afterHabitChange(context, s, h, wasDone: was);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = dk(now);
    final type = (h['type'] as String?) ?? 'yesno';
    final color = Color(habitColor(h));
    final done = HabitCore.done(h, now);
    switch (type) {
      case 'count':
      case 'frequency':
        return FilledButton.tonal(
          onPressed: () => _do(() => s.addHabitValue(h, today, 1)),
          onLongPress: () => showHabitDay(context, s, h, now),
          child: const Text('+1'),
        );
      case 'duration':
        final started = h['timer'] as int?;
        if (started != null) {
          final secs = (now.millisecondsSinceEpoch - started) ~/ 1000;
          final t = HabitCore.target(h, now);
          final logged = (HabitCore.value(h, now) ?? 0) * 60;
          final left = t == null ? null : (t * 60 - logged - secs).round();
          final shown = left != null && left > 0 ? left : secs;
          final label = '${left != null && left > 0 ? '' : '+'}${shown ~/ 60}:${(shown % 60).toString().padLeft(2, '0')}';
          return FilledButton.icon(
            onPressed: () => _do(() async {
              final minutes = ((now.millisecondsSinceEpoch - started) / 60000).ceil();
              h.remove('timer');
              await s.addHabitValue(h, today, minutes);
            }),
            icon: const Icon(Icons.stop),
            label: Text(label),
          );
        }
        return IconButton.filledTonal(
          tooltip: 'Start timer',
          onPressed: () {
            Haptics.tap();
            h['timer'] = now.millisecondsSinceEpoch;
            s.save();
          },
          icon: const Icon(Icons.play_arrow),
        );
      case 'time':
        return IconButton.filledTonal(
          tooltip: done ? 'Done' : 'Done now',
          onPressed: done
              ? null
              : () => _do(() => s.logHabit(h, today, {'at': '${two(now.hour)}:${two(now.minute)}'})),
          icon: Icon(done ? Icons.check : Icons.alarm_on),
        );
      case 'yesno':
      case 'auto':
        return IconButton(
          tooltip: done ? 'Undo' : 'Done',
          onPressed: () => _do(() => s.logHabit(h, today, done ? null : 'yes')),
          icon: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: color, size: 30),
        );
      default:
        // Amounts, ratings, percentages, limits and checklists: open the day's entry.
        return IconButton.filledTonal(
          tooltip: 'Log',
          onPressed: () => showHabitDay(context, s, h, now),
          icon: Icon(type == 'checklist' ? Icons.checklist : (type == 'rating' ? Icons.star_outline : Icons.add)),
        );
    }
  }
}

/// A habit as one row of today's list: progress ring, name, how it stands, and its quick control.
class HabitTodayRow extends StatelessWidget {
  const HabitTodayRow({super.key, required this.store, required this.habit, this.flat = false, this.onOpen});
  final Store store;
  final Rec habit;

  /// Flat inside another card (Home); its own card in lists.
  final bool flat;

  /// Opens the habit's page (given by the habits screen, which owns that page).
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final h = habit;
    final now = DateTime.now();
    final color = Color(habitColor(h));
    final scheduled = HabitCore.scheduled(h, now);
    final p = HabitCore.progress(h, now) ?? 0;
    final streak = HabitCore.currentStreak(h, now);
    final unit = HabitCore.unit(h);
    final tt = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final period = HabitCore.byPeriod(h)
        ? '${HabitCore.periodCount(h, HabitCore.periodStart(h, now))} of ${HabitCore.periodTarget(h)} this ${HabitCore.kind(h)}'
        : null;
    final row = InkWell(
      onTap: onOpen ??
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => HabitPage(store: store, id: h['id'] as int))),
      onLongPress: () => showHabitDay(context, store, h, now),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: flat ? 0 : 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(alignment: Alignment.center, children: [
                CircularProgressIndicator(
                  value: scheduled ? p : 0,
                  strokeWidth: 3.5,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.18),
                ),
                Icon(habitIcon(h), size: 18, color: scheduled ? color : muted),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h['name'] as String, style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    !scheduled
                        ? 'Not today: ${HabitCore.describe(h)}'
                        : [habitDayText(h, now), if (period != null) period, if (streak > 0) '$streak $unit${streak == 1 ? '' : 's'} streak']
                            .join(', '),
                    style: tt.bodySmall?.copyWith(color: muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (scheduled) HabitQuickControl(store: store, habit: h),
          ],
        ),
      ),
    );
    return flat ? row : Card(child: row);
  }
}

Future<String?> _keepPhoto(XFile f) async {
  if (kIsWeb) return null;
  final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/habits');
  await dir.create(recursive: true);
  final path = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
  await File(f.path).copy(path);
  return path;
}

/// Everything about one habit on one day: the amount (by type), a note, a photo, or mark it a rest day
/// or missed.
Future<void> showHabitDay(BuildContext context, Store s, Rec h, DateTime day) async {
  final key = dk(day);
  final type = (h['type'] as String?) ?? 'yesno';
  final e = Map<String, dynamic>.from(HabitCore.entry(h, key) ?? {});
  final unit = (h['unit'] as String?) ?? '';
  final target = HabitCore.target(h, day);
  final value = TextEditingController(text: e['v'] == null ? '' : fmtNum(e['v'] as num));
  final note = TextEditingController(text: e['note'] as String?);
  final steps = ((h['items'] as List?) ?? const []).cast<String>();
  final checked = List<bool>.generate(steps.length, (i) {
    final l = (e['items'] as List?) ?? const [];
    return i < l.length && l[i] == true;
  });
  var rating = (e['v'] as num?)?.round();
  var at = e['at'] as String?;
  var done = e['done'] == true || (type == 'yesno' && HabitCore.done(h, day));
  String? photo = e['photo'] as String?;
  final scale = ((h['scale'] as num?) ?? 10).round();
  final wasDone = HabitCore.done(h, day);

  Future<void> save(Object? v) async {
    await s.logHabit(h, key, v);
    if (context.mounted) afterHabitChange(context, s, h, wasDone: wasDone);
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final tt = Theme.of(ctx).textTheme;
        Map<String, dynamic> build() {
          final out = <String, dynamic>{};
          switch (type) {
            case 'yesno':
            case 'auto':
              if (done) out['done'] = true;
            case 'time':
              if (at != null) out['at'] = at;
            case 'checklist':
              out['items'] = checked;
            case 'rating':
              if (rating != null) out['v'] = rating;
            default:
              final v = num.tryParse(value.text.trim().replaceAll(',', '.'));
              if (v != null) out['v'] = v;
          }
          if (note.text.trim().isNotEmpty) out['note'] = note.text.trim();
          if (photo != null) out['photo'] = photo;
          return out;
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h['name'] as String, style: tt.titleLarge),
                Text(
                  '${dk(day) == dk(DateTime.now()) ? 'Today' : '${day.day}/${day.month}/${day.year}'}'
                  '${target == null || const ['yesno', 'time', 'checklist', 'rating'].contains(type) ? '' : ', goal ${type == 'limit' ? 'at most ' : ''}${fmtNum(target)} $unit'}',
                  style: tt.bodyMedium,
                ),
                const SizedBox(height: 16),
                switch (type) {
                  'yesno' || 'auto' => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Done'),
                      value: done,
                      onChanged: (v) => setS(() => done = v),
                    ),
                  'time' => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule),
                      title: Text(at == null ? 'Set the time you did it' : 'Done at ${time12(at!)}'),
                      subtitle: h['by'] == null ? null : Text('Goal: by ${time12(h['by'] as String)}'),
                      onTap: () async {
                        final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                        if (t != null) setS(() => at = '${two(t.hour)}:${two(t.minute)}');
                      },
                    ),
                  'checklist' => Column(children: [
                      for (var i = 0; i < steps.length; i++)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: checked[i],
                          title: Text(steps[i]),
                          onChanged: (v) => setS(() => checked[i] = v ?? false),
                        ),
                    ]),
                  'rating' => Wrap(spacing: 6, runSpacing: 6, children: [
                      for (var i = 1; i <= scale; i++)
                        ChoiceChip(label: Text('$i'), selected: rating == i, onSelected: (_) => setS(() => rating = i)),
                    ]),
                  _ => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: value,
                          autofocus: e['v'] == null,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: 'Total ${type == 'duration' ? 'minutes' : unit}'.trim()),
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, children: [
                          for (final step in _quickSteps(type, target))
                            ActionChip(
                              label: Text('+${fmtNum(step)}'),
                              onPressed: () => setS(() {
                                final v = num.tryParse(value.text.trim().replaceAll(',', '.')) ?? 0;
                                value.text = fmtNum(v + step);
                              }),
                            ),
                        ]),
                      ],
                    ),
                },
                const SizedBox(height: 12),
                TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)'), maxLines: 2),
                const SizedBox(height: 8),
                Row(children: [
                  if (photo != null && !kIsWeb)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(photo!), width: 56, height: 56, fit: BoxFit.cover),
                      ),
                    ),
                  if (!kIsWeb)
                    TextButton.icon(
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(photo == null ? 'Add progress photo' : 'Change photo'),
                      onPressed: () async {
                        final f = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 80);
                        if (f == null) return;
                        final kept = await _keepPhoto(f);
                        if (kept != null) setS(() => photo = kept);
                      },
                    ),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final b = build();
                      await save(b.isEmpty ? null : b);
                    },
                    child: const Text('Save'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await save({'skip': true, if (note.text.trim().isNotEmpty) 'note': note.text.trim()});
                    },
                    child: const Text('Rest day'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await save({'miss': true, if (note.text.trim().isNotEmpty) 'note': note.text.trim()});
                    },
                    child: const Text('Missed'),
                  ),
                  if (HabitCore.entry(h, key) != null)
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await save(null);
                      },
                      child: const Text('Clear day'),
                    ),
                ]),
              ],
            ),
          ),
        );
      },
    ),
  );
}

List<num> _quickSteps(String type, num? target) => switch (type) {
      'duration' => [5, 15, 30],
      'quantity' => [0.25, 0.5, 1],
      'distance' => [0.5, 1, 5],
      'percent' => [10, 25],
      'limit' => [15, 30, 60],
      _ => [1, 5, 10],
    };
