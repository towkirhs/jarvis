import 'package:flutter/material.dart';

import 'brain.dart';
import 'store.dart';

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

  Store get s => widget.store;

  @override
  void dispose() {
    _askCtrl.dispose();
    super.dispose();
  }

  void _say(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _ask() async {
    final q = _askCtrl.text.trim();
    if (q.isEmpty) return;
    if (s.apiKey.isEmpty) {
      _say('Add your Gemini key in Settings first.');
      return;
    }
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

  Future<void> _summarize(String day) async {
    if (s.apiKey.isEmpty) {
      _say('Add your Gemini key in Settings first.');
      return;
    }
    try {
      await Brain.summarize(s, day);
    } catch (e) {
      _say('Could not write the summary: $e');
    }
  }

  void _showOriginal(Rec c) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('What you said'),
        content: Text(c['raw'] as String),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final q = _search.toLowerCase();
          final onThisDay = s.onThisDay();
          final days = <String>[];
          for (final d in s.journalDays()) {
            final entries = _entries(d, q);
            if (entries.isNotEmpty) days.add(d);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Journal', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search your journal',
                  border: OutlineInputBorder(),
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
                        hintText: 'Ask your journal, like: when did I last go to the gym?',
                        border: OutlineInputBorder(),
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
              if (_answer != null)
                Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_answer!))),
              if (onThisDay.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('On this day', style: TextStyle(fontWeight: FontWeight.bold)),
                        for (final c in onThisDay)
                          Text('${fromMs(c['ts'] as int).year}: ${c['cleaned']}'),
                      ],
                    ),
                  ),
                ),
              if (days.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No entries yet.')),
              for (final d in days) _day(d, q),
            ],
          );
        },
      );

  List<Rec> _entries(String day, String q) => s
      .capturesOn(day)
      .where((c) => q.isEmpty || c['cleaned'].toString().toLowerCase().contains(q) || c['raw'].toString().toLowerCase().contains(q))
      .toList();

  Widget _day(String day, String q) {
    final summary = s.summaries[day] as String?;
    return ExpansionTile(
      title: Text(day),
      subtitle: summary == null ? null : Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
      children: [
        if (summary != null) Padding(padding: const EdgeInsets.all(12), child: Text(summary)),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _summarize(day),
            child: Text(summary == null ? 'Write summary' : 'Rewrite summary'),
          ),
        ),
        for (final c in _entries(day, q))
          ListTile(
            dense: true,
            title: Text(c['cleaned'] as String),
            subtitle: Text(clock(c['ts'] as int)),
            onTap: () => _showOriginal(c),
          ),
      ],
    );
  }
}
