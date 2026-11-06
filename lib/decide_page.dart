import 'package:flutter/material.dart';

import 'brain.dart';
import 'decide.dart';
import 'haptics.dart';
import 'store.dart';

/// Decisions, not conversation: describe the choice, get a verdict with probabilities.
class DecidePage extends StatefulWidget {
  const DecidePage({super.key, required this.store, this.initial});
  final Store store;
  final String? initial;

  @override
  State<DecidePage> createState() => _DecidePageState();
}

class _DecidePageState extends State<DecidePage> {
  late final _situation = TextEditingController(text: widget.initial);
  final _option = TextEditingController();
  final _options = <String>[];
  List<Answer>? _answers;
  String? _error;
  bool _busy = false;

  Store get s => widget.store;

  @override
  void dispose() {
    _situation.dispose();
    _option.dispose();
    super.dispose();
  }

  void _addOption() {
    final o = _option.text.trim();
    if (o.isEmpty || _options.contains(o) || _options.length >= 6) return;
    setState(() => _options.add(o));
    _option.clear();
  }

  Future<void> _decide() async {
    _addOption();
    final text = _situation.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _answers = null;
    });
    try {
      final answers = await Brain.decide(s, text, options: List.of(_options));
      Haptics.success();
      setState(() => _answers = answers);
    } catch (e) {
      setState(() => _error = s.apiKey.isEmpty ? 'Add your Gemini key in Settings first.' : 'Could not decide: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Decide')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _situation,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Should I go to the wedding on Friday or study for the exam?'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _option,
                  onSubmitted: (_) => _addOption(),
                  decoration: const InputDecoration(hintText: 'Options (optional): add one'),
                ),
              ),
              IconButton(onPressed: _addOption, icon: const Icon(Icons.add)),
            ],
          ),
          if (_options.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                for (final o in _options) InputChip(label: Text(o), onDeleted: () => setState(() => _options.remove(o))),
              ],
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _decide,
            icon: const Icon(Icons.balance),
            label: const Text('Decide'),
          ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!)),
          if (_answers != null) ...[
            const SizedBox(height: 20),
            DecisionCard(store: s, answers: _answers!),
          ],
          const SizedBox(height: 24),
          Text(
            'Jarvis weighs your schedule, money, habits, promises and past decisions, and answers with odds. '
            'Below ${(s.sureEnough * 100).round()}% it calls it too close and leaves it to you.',
            style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// The verdict: the pick in big type, every option's odds as bars, and how much it matters.
class DecisionCard extends StatelessWidget {
  const DecisionCard({super.key, required this.store, required this.answers});
  final Store store;
  final List<Answer> answers;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pick = answers.first;
    final impact = answers.length > 1 ? answers[1] : null;
    final sure = pick.confidence >= store.sureEnough;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sure ? 'Decision' : 'Too close to call', style: tt.labelLarge?.copyWith(color: scheme.primary)),
            const SizedBox(height: 4),
            Text(sure ? pick.pick : 'Your call', style: tt.headlineMedium),
            const SizedBox(height: 12),
            for (final e in pick.probs.entries) ...[
              Row(
                children: [
                  Expanded(child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text('${(e.value * 100).round()}%', style: tt.labelLarge),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: e.value,
                  minHeight: 8,
                  color: e.key == pick.pick ? scheme.primary : scheme.outline,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (impact != null)
              Text(
                'Stakes ${impact.value.toStringAsFixed(1)} of 5'
                '${impact.value < 2.5 ? ' · low, decide fast and move on' : ''}',
                style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
