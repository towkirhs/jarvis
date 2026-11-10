import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'ai.dart';
import 'haptics.dart';
import 'brain.dart';
import 'habit_core.dart';
import 'store.dart';

const moodFaces = ['', '😞', '😕', '😐', '🙂', '😄'];
const moodLabels = ['', 'Awful', 'Bad', 'Okay', 'Good', 'Great'];
const moodColors = [
  Colors.transparent,
  Color(0xFFE57373),
  Color(0xFFFFB74D),
  Color(0xFFFFE082),
  Color(0xFFAED581),
  Color(0xFF66BB6A),
];
const defaultActivities = [
  'Family', 'Friends', 'Study', 'Work', 'Exercise', 'Good sleep', 'Reading', 'Prayer',
  'Outdoors', 'Gaming', 'Social media', 'Sick', 'Date', 'Travel',
];
const journalPrompts = [
  'What are three things you are grateful for today?',
  'What made you smile today?',
  'What is one thing you want to get done tomorrow, and why does it matter?',
  'What drained your energy today, and what gave you energy?',
  'What did you learn today?',
  'What would make tomorrow a great day?',
  'Who helped you recently, and how?',
  'What is worrying you? Write it down and leave it here.',
  'What went well this week?',
  'If today had a title, what would it be?',
  'What is something you are proud of, however small?',
  'What did you avoid today, and what is the first step to face it?',
];
const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
  'October', 'November', 'December'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _niceDay(String day) {
  final d = DateTime.parse(day);
  return '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// Copies a picked photo into the app's own folder so it outlives the picker's cache. Not on the web.
Future<String?> _keepPhoto(XFile f) async {
  if (kIsWeb) return null;
  final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/journal');
  await dir.create(recursive: true);
  final path = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
  await File(f.path).copy(path);
  return path;
}

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key, required this.store});
  final Store store;

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final _askCtrl = TextEditingController();
  String _search = '';
  String? _answer;
  bool _asking = false;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  Store get s => widget.store;

  @override
  void dispose() {
    _askCtrl.dispose();
    super.dispose();
  }

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _ask() async {
    final q = _askCtrl.text.trim();
    if (q.isEmpty) return;
    if (!AI.available(s)) return _say('Set up an AI in Settings, AI models first.');
    setState(() => _asking = true);
    try {
      final a = await Brain.ask(s, q);
      if (mounted) setState(() => _answer = a);
    } catch (e) {
      if (mounted) setState(() => _answer = 'Could not answer: $e');
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  Future<void> _reflect() async {
    if (!AI.available(s)) return _say('Set up an AI in Settings, AI models first.');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    String text;
    try {
      text = await Brain.reflectWeek(s);
    } catch (e) {
      text = 'Could not write the reflection: $e';
    }
    if (!mounted) return;
    Navigator.pop(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your week'),
        content: SingleChildScrollView(child: Text(text)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  bool _matches(String day, String q) {
    if (q.isEmpty) return true;
    bool has(Object? v) => (v ?? '').toString().toLowerCase().contains(q);
    return s.entriesOn(day).any((e) => has(e['text']) || has((e['tags'] as List?)?.join(' '))) ||
        s.capturesOn(day).any((c) => has(c['cleaned']) || has(c['raw'])) ||
        has(s.summaries[day]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => openEntryEditor(context, s),
          icon: const Icon(Icons.edit),
          label: const Text('Write'),
        ),
        body: ListenableBuilder(
          listenable: s,
          builder: (context, _) {
            final q = _search.toLowerCase();
            final days = s.journalDays().where((d) => _matches(d, q)).toList();
            final streak = s.journalStreak();
            final past = s.onThisDay();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: [
                Row(
                  children: [
                    Text('Journal', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(width: 8),
                    if (streak > 0) Text('🔥 $streak', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Insights',
                      icon: const Icon(Icons.insights),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => JournalInsightsPage(store: s)),
                      ),
                    ),
                    IconButton(tooltip: 'Reflect on my week', icon: const Icon(Icons.auto_awesome), onPressed: _reflect),
                  ],
                ),
                const SizedBox(height: 8),
                _MoodCalendar(
                  store: s,
                  month: _month,
                  onMonth: (m) => setState(() => _month = m),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search your journal',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _askCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Ask: when did I last feel this good?',
                          isDense: true,
                        ),
                        onSubmitted: (_) => _ask(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _asking ? null : _ask,
                      icon: _asking
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.question_answer),
                    ),
                  ],
                ),
                if (_answer != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_answer!))),
                if (past.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('On this day', style: TextStyle(fontWeight: FontWeight.bold)),
                          for (final (year, text) in past) Text('$year: $text', maxLines: 3, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ),
                if (days.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nothing yet. Tap Write, or just talk to Jarvis. Everything you say lands here.'),
                  ),
                for (final d in days.take(60)) _dayCard(context, d),
              ],
            );
          },
        ),
      );

  Widget _dayCard(BuildContext context, String day) {
    final mood = s.dayMood(day);
    final entries = s.entriesOn(day);
    final caps = s.capturesOn(day);
    final summary = s.summaries[day] as String?;
    final preview = summary ??
        [...entries.map((e) => e['text'] as String), ...caps.map((c) => c['cleaned'] as String)].join('  ·  ');
    final photos = entries.where((e) => e['photo'] != null).length;
    return Card(
      child: ListTile(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DayPage(store: s, day: day))),
        leading: CircleAvatar(
          backgroundColor: mood == null ? Theme.of(context).colorScheme.surfaceContainerHighest : moodColors[mood],
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          child: Text(mood == null ? '${DateTime.parse(day).day}' : moodFaces[mood]),
        ),
        title: Text(_niceDay(day)),
        subtitle: Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: photos > 0 ? const Icon(Icons.photo_outlined, size: 18) : null,
      ),
    );
  }
}

/// A month of days coloured by mood. Tap a day to open it.
class _MoodCalendar extends StatelessWidget {
  const _MoodCalendar({required this.store, required this.month, required this.onMonth});
  final Store store;
  final DateTime month;
  final void Function(DateTime) onMonth;

  @override
  Widget build(BuildContext context) {
    final days = store.journalDays().toSet();
    final first = DateTime(month.year, month.month, 1);
    final count = DateTime(month.year, month.month + 1, 0).day;
    final scheme = Theme.of(context).colorScheme;
    final today = dayKey(DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(tooltip: 'Previous',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => onMonth(DateTime(month.year, month.month - 1)),
                ),
                Expanded(child: Center(child: Text('${_months[month.month - 1]} ${month.year}'))),
                IconButton(tooltip: 'Next',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => onMonth(DateTime(month.year, month.month + 1)),
                ),
              ],
            ),
            Row(children: [for (final w in _weekdays) Expanded(child: Center(child: Text(w[0], style: const TextStyle(fontSize: 11))))]),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 1; i < first.weekday; i++) const SizedBox(),
                for (var d = 1; d <= count; d++)
                  Builder(builder: (context) {
                    final key = dayKey(DateTime(month.year, month.month, d));
                    final mood = store.dayMood(key);
                    final has = days.contains(key);
                    return InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DayPage(store: store, day: key))),
                      child: Container(
                        margin: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: mood != null ? moodColors[mood] : (has ? scheme.primaryContainer : null),
                          border: key == today ? Border.all(color: scheme.primary, width: 2) : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(mood != null ? moodFaces[mood] : '$d', style: const TextStyle(fontSize: 13)),
                      ),
                    );
                  }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One day: mood, written entries with photos, what Jarvis heard, what you did, and the AI summary.
class DayPage extends StatelessWidget {
  const DayPage({super.key, required this.store, required this.day});
  final Store store;
  final String day;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_niceDay(day))),
        floatingActionButton: FloatingActionButton(
          onPressed: () => openEntryEditor(context, store, day: DateTime.parse(day)),
          child: const Icon(Icons.edit),
        ),
        body: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final entries = store.entriesOn(day);
            final caps = store.capturesOn(day);
            final facts = store.dayFacts(day);
            final summary = store.summaries[day] as String?;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
              children: [
                for (final e in entries) _entryCard(context, e),
                if (facts.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Your day', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          for (final f in facts) Text('• $f'),
                        ],
                      ),
                    ),
                  ),
                if (caps.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('What you told Jarvis', style: Theme.of(context).textTheme.titleSmall),
                  for (final c in caps)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(c['cleaned'] as String),
                      subtitle: Text(c['reply'] == null ? clock(c['ts'] as int) : '${clock(c['ts'] as int)}  ·  Jarvis: ${c['reply']}'),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('What you said'),
                          content: Text(c['raw'] as String),
                          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Summary', style: TextStyle(fontWeight: FontWeight.bold)),
                        if (summary != null) Text(summary),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () async {
                              if (!AI.available(store)) return;
                              try {
                                await Brain.summarize(store, day);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not write it: $e')));
                                }
                              }
                            },
                            child: Text(summary == null ? 'Write summary' : 'Rewrite'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );

  Widget _entryCard(BuildContext context, Rec e) {
    final mood = e['mood'] as int?;
    final tags = ((e['tags'] as List?) ?? []).cast<String>();
    final photo = e['photo'] as String?;
    return Card(
      child: InkWell(
        onTap: () => openEntryEditor(context, store, entry: e),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (mood != null) Text('${moodFaces[mood]} ${moodLabels[mood]}   ', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(clock(e['ts'] as int), style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              if (e['prompt'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(e['prompt'] as String, style: const TextStyle(fontStyle: FontStyle.italic)),
                ),
              if ((e['text'] as String).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(e['text'] as String)),
              if (photo != null && !kIsWeb && File(photo).existsSync())
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(photo))),
                ),
              if (tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(spacing: 6, children: [for (final t in tags) Chip(label: Text(t), visualDensity: VisualDensity.compact)]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Write or edit an entry: mood, activities, a prompt, text and a photo.
Future<void> openEntryEditor(BuildContext context, Store s, {Rec? entry, DateTime? day}) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => _EntryEditor(store: s, entry: entry, day: day)));

class _EntryEditor extends StatefulWidget {
  const _EntryEditor({required this.store, this.entry, this.day});
  final Store store;
  final Rec? entry;
  final DateTime? day;

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late final TextEditingController _text = TextEditingController(text: widget.entry?['text'] as String? ?? '');
  late int? _mood = widget.entry?['mood'] as int?;
  late final Set<String> _tags = {...((widget.entry?['tags'] as List?) ?? []).cast<String>()};
  late String? _prompt = widget.entry?['prompt'] as String?;
  late String? _photo = widget.entry?['photo'] as String?;
  bool _toJarvis = false;

  Store get s => widget.store;

  List<String> get _activities => {
        ...defaultActivities,
        for (final e in s.list('entries')) ...((e['tags'] as List?) ?? []).cast<String>(),
        ..._tags,
      }.toList();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    final f = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 80);
    if (f == null) return;
    final kept = await _keepPhoto(f);
    if (kept != null) setState(() => _photo = kept);
  }

  Future<void> _newActivity() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New activity'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Add'))],
      ),
    );
    if (name != null && name.isNotEmpty) setState(() => _tags.add(name));
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty && _mood == null && _photo == null) {
      Navigator.pop(context);
      return;
    }
    final e = widget.entry;
    if (e == null) {
      final now = DateTime.now();
      final d = widget.day;
      final ts = d == null || dayKey(d) == dayKey(now)
          ? now.millisecondsSinceEpoch
          : DateTime(d.year, d.month, d.day, 21).millisecondsSinceEpoch;
      final r = {
        'id': s.nextId(),
        'ts': ts,
        'text': text,
        'mood': _mood,
        'tags': _tags.toList(),
        'prompt': _prompt,
        'photo': _photo,
      };
      s.list('entries').add(r);
      s.logAction('Journal entry${_mood == null ? '' : ' (${moodLabels[_mood!]})'}', [
        {'op': 'rm', 'col': 'entries', 'id': r['id']},
      ]);
      s.save();
      Haptics.tap();
      if (_toJarvis && text.isNotEmpty) await Brain.capture(s, text, source: 'journal');
    } else {
      await s.updateRec('entries', e, 'Edited journal entry', (r) {
        r['text'] = text;
        r['mood'] = _mood;
        r['tags'] = _tags.toList();
        r['prompt'] = _prompt;
        r['photo'] = _photo;
      });
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.entry == null ? 'New entry' : 'Edit entry'),
          actions: [
            if (widget.entry != null)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  Haptics.warn();
                  s.removeRec('entries', widget.entry!, 'Deleted journal entry');
                  Navigator.pop(context);
                },
              ),
            TextButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('How are you?'),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var m = 1; m <= 5; m++)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _mood = _mood == m ? null : m),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _mood == m ? moodColors[m] : null,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(children: [
                        Text(moodFaces[m], style: const TextStyle(fontSize: 30)),
                        Text(moodLabels[m], style: const TextStyle(fontSize: 11)),
                      ]),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('What did you do?'),
            Wrap(
              spacing: 6,
              children: [
                for (final a in _activities)
                  FilterChip(
                    label: Text(a),
                    selected: _tags.contains(a),
                    onSelected: (on) => setState(() => on ? _tags.add(a) : _tags.remove(a)),
                  ),
                ActionChip(avatar: const Icon(Icons.add, size: 16), label: const Text('New'), onPressed: _newActivity),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(_prompt ?? 'Write freely, or take a prompt.',
                      style: TextStyle(fontStyle: _prompt == null ? FontStyle.normal : FontStyle.italic)),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.lightbulb_outline),
                  label: Text(_prompt == null ? 'Prompt' : 'Another'),
                  onPressed: () => setState(() => _prompt = journalPrompts[Random().nextInt(journalPrompts.length)]),
                ),
              ],
            ),
            TextField(
              controller: _text,
              autofocus: widget.entry == null,
              minLines: 8,
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Dear diary...'),
            ),
            const SizedBox(height: 12),
            if (!kIsWeb)
              _photo == null
                  ? OutlinedButton.icon(onPressed: _addPhoto, icon: const Icon(Icons.add_a_photo), label: const Text('Add a photo'))
                  : Stack(children: [
                      ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(_photo!))),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: IconButton.filled(onPressed: () => setState(() => _photo = null), icon: const Icon(Icons.close)),
                      ),
                    ]),
            if (widget.entry == null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Let Jarvis pick out tasks and plans'),
                subtitle: const Text('Off: this stays a private journal entry.'),
                value: _toJarvis,
                onChanged: (v) {
                  Haptics.toggle(v);
                  setState(() => _toJarvis = v);
                },
              ),
          ],
        ),
      );
}

/// Mood over time, by weekday, and what goes with your better days.
class JournalInsightsPage extends StatelessWidget {
  const JournalInsightsPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    final s = store;
    final now = DateTime.now();
    final moods = <String, int>{};
    for (final d in s.journalDays()) {
      final m = s.dayMood(d);
      if (m != null) moods[d] = m;
    }
    final last30 = [for (var i = 29; i >= 0; i--) dayKey(DateTime(now.year, now.month, now.day - i))];
    final avg = moods.isEmpty ? 0.0 : moods.values.reduce((a, b) => a + b) / moods.length;

    final byWeekday = List.generate(7, (_) => <int>[]);
    moods.forEach((d, m) => byWeekday[DateTime.parse(d).weekday - 1].add(m));

    // Average mood on days with each activity or habit, compared with the overall average.
    final links = <(String, double, int)>[];
    void compare(String name, bool Function(String day) did) {
      final withIt = [for (final e in moods.entries) if (did(e.key)) e.value];
      if (withIt.length < 3) return;
      links.add((name, withIt.reduce((a, b) => a + b) / withIt.length - avg, withIt.length));
    }

    final tags = {for (final e in s.list('entries')) ...((e['tags'] as List?) ?? []).cast<String>()};
    for (final t in tags) {
      compare(t, (d) => s.entriesOn(d).any((e) => ((e['tags'] as List?) ?? []).contains(t)));
    }
    for (final h in s.list('habits')) {
      compare('${h['name']} (habit)', (d) => HabitCore.done(h, DateTime.parse(d)));
    }
    compare('Focused 1h+', (d) =>
        s.list('focus').where((f) => dayKey(fromMs(f['start'] as int)) == d).fold<int>(0, (a, f) => a + (f['minutes'] as int)) >= 60);
    links.sort((a, b) => b.$2.compareTo(a.$2));

    final words = s.list('entries').fold<int>(0, (a, e) => a + (e['text'] as String).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length);
    final style = Theme.of(context).textTheme.titleMedium;

    return Scaffold(
      appBar: AppBar(title: const Text('Journal insights')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${s.list('entries').length} entries  ·  $words words  ·  🔥 ${s.journalStreak()} day streak'),
          const SizedBox(height: 16),
          Text('Mood, last 30 days', style: style),
          const SizedBox(height: 8),
          SizedBox(
            height: 90,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in last30)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      height: moods[d] == null ? 2 : 16.0 * moods[d]!,
                      color: moods[d] == null ? Colors.grey.withValues(alpha: 0.3) : moodColors[moods[d]!],
                    ),
                  ),
              ],
            ),
          ),
          if (moods.isNotEmpty) Text('Average: ${moodFaces[avg.round()]} ${avg.toStringAsFixed(1)} of 5'),
          const SizedBox(height: 16),
          Text('Mood by weekday', style: style),
          for (var i = 0; i < 7; i++)
            Row(children: [
              SizedBox(width: 40, child: Text(_weekdays[i])),
              Expanded(
                child: byWeekday[i].isEmpty
                    ? const Text('-')
                    : Builder(builder: (_) {
                        final a = byWeekday[i].reduce((x, y) => x + y) / byWeekday[i].length;
                        return FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: a / 5,
                          child: Container(height: 14, color: moodColors[a.round()]),
                        );
                      }),
              ),
            ]),
          const SizedBox(height: 16),
          Text('What goes with your better days', style: style),
          if (links.isEmpty)
            const Text('Log a mood and activities for a couple of weeks to see this. Each needs at least 3 days.'),
          for (final (name, diff, n) in links)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(diff >= 0 ? Icons.trending_up : Icons.trending_down, color: diff >= 0 ? Colors.green : Colors.red),
              title: Text(name),
              subtitle: Text('$n days'),
              trailing: Text('${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)} mood'),
            ),
        ],
      ),
    );
  }
}
