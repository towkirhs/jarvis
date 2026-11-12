import 'package:flutter/material.dart';

import 'haptics.dart';
import 'productivity.dart';
import 'store.dart';

/// Deck names in use, A to Z.
List<String> recallDecks(Store s) => {for (final c in s.list('cards')) c['deck'] as String}.toList()..sort();

int dueCards(Store s, {String? deck}) =>
    s.list('cards').where((c) => (deck == null || c['deck'] == deck) && Recall.isDue(c, DateTime.now())).length;

/// Flashcards for active recall: decks, what is due today, and a review that asks before it shows.
class RecallPage extends StatelessWidget {
  const RecallPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final s = store;
          final tt = Theme.of(context).textTheme;
          final scheme = Theme.of(context).colorScheme;
          final decks = recallDecks(s);
          final due = dueCards(s);
          return Scaffold(
            appBar: AppBar(title: const Text('Active recall')),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => editCard(context, s),
              icon: const Icon(Icons.add),
              label: const Text('Card'),
            ),
            body: decks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Write a question on the front and the answer on the back. Jarvis asks you before showing the answer, '
                        'and brings each card back just before you would forget it.',
                        textAlign: TextAlign.center,
                        style: tt.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      Text(due == 0 ? 'All caught up' : '$due ${due == 1 ? 'card' : 'cards'} to review today', style: tt.headlineSmall),
                      const SizedBox(height: 12),
                      if (due > 0)
                        FilledButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewPage(store: s))),
                          icon: const Icon(Icons.psychology_alt_outlined),
                          label: const Text('Review all'),
                        ),
                      const SizedBox(height: 8),
                      for (final d in decks)
                        Builder(builder: (context) {
                          final n = s.list('cards').where((c) => c['deck'] == d).length;
                          final dd = dueCards(s, deck: d);
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.style_outlined),
                              title: Text(d, style: tt.titleMedium),
                              subtitle: Text('$n ${n == 1 ? 'card' : 'cards'}${dd > 0 ? '  ·  $dd due' : ''}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DeckPage(store: s, deck: d))),
                            ),
                          );
                        }),
                    ],
                  ),
          );
        },
      );
}

/// One deck's cards, and a review of just this deck.
class DeckPage extends StatelessWidget {
  const DeckPage({super.key, required this.store, required this.deck});
  final Store store;
  final String deck;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final s = store;
          final cards = s.list('cards').where((c) => c['deck'] == deck).toList();
          final due = dueCards(s, deck: deck);
          return Scaffold(
            appBar: AppBar(title: Text(deck)),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => editCard(context, s, deck: deck),
              icon: const Icon(Icons.add),
              label: const Text('Card'),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                FilledButton.tonalIcon(
                  onPressed: cards.isEmpty
                      ? null
                      : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewPage(store: s, deck: deck, all: due == 0))),
                  icon: const Icon(Icons.psychology_alt_outlined),
                  label: Text(due > 0 ? 'Review $due due' : 'Practise all ${cards.length}'),
                ),
                const SizedBox(height: 8),
                if (cards.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No cards left in this deck.')),
                for (final c in cards)
                  Card(
                    child: ListTile(
                      title: Text('${c['q']}'),
                      subtitle: Text(Recall.isDue(c, DateTime.now()) ? 'Due today' : 'Next: ${dayKey(fromMs(c['due'] as int))}  ·  box ${c['box']}'),
                      onTap: () => editCard(context, s, card: c),
                    ),
                  ),
              ],
            ),
          );
        },
      );
}

Future<void> editCard(BuildContext context, Store s, {Rec? card, String? deck}) async {
  final q = TextEditingController(text: card?['q'] as String? ?? '');
  final a = TextEditingController(text: card?['a'] as String? ?? '');
  final d = TextEditingController(text: card?['deck'] as String? ?? deck ?? '');
  final decks = recallDecks(s);
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(card == null ? 'New card' : 'Edit card'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: d, decoration: const InputDecoration(labelText: 'Deck', hintText: 'Anatomy, Spanish…')),
            if (decks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final x in decks)
                  ChoiceChip(label: Text(x), selected: d.text.trim() == x, onSelected: (_) => setD(() => d.text = x)),
              ]),
            ],
            TextField(controller: q, autofocus: true, maxLines: null, decoration: const InputDecoration(labelText: 'Question (front)')),
            TextField(
              controller: a,
              maxLines: null,
              decoration: InputDecoration(labelText: 'Answer (back)', errorText: error),
            ),
          ]),
        ),
        actions: [
          if (card != null)
            TextButton(
              onPressed: () {
                Haptics.warn();
                s.removeRec('cards', card, 'Deleted a flashcard');
                Navigator.pop(ctx);
              },
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final deckName = d.text.trim().isEmpty ? 'General' : d.text.trim();
              if (q.text.trim().isEmpty || a.text.trim().isEmpty) {
                return setD(() => error = Haptics.rejected() ?? 'Write both sides');
              }
              if (card == null) {
                final rec = {
                  'id': s.nextId(),
                  'deck': deckName,
                  'q': q.text.trim(),
                  'a': a.text.trim(),
                  'box': 0,
                  'due': DateTime.now().millisecondsSinceEpoch,
                };
                s.list('cards').add(rec);
                s.logAction('Added a flashcard to $deckName', [
                  {'op': 'rm', 'col': 'cards', 'id': rec['id']},
                ]);
                s.save();
                Haptics.tap();
                if (ctx.mounted) Navigator.pop(ctx);
                // Keep adding to the same deck.
                if (context.mounted) editCard(context, s, deck: deckName);
                return;
              }
              await s.updateRec('cards', card, 'Edited a flashcard', (r) {
                r['deck'] = deckName;
                r['q'] = q.text.trim();
                r['a'] = a.text.trim();
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// Asks each due card. You answer in your head, then check: a miss comes back at the end of this session.
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.store, this.deck, this.all = false});
  final Store store;
  final String? deck;

  /// Practise every card in the deck, not only the due ones. Practice does not move cards between boxes.
  final bool all;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late final List<Rec> _queue = widget.store
      .list('cards')
      .where((c) => (widget.deck == null || c['deck'] == widget.deck) && (widget.all || Recall.isDue(c, DateTime.now())))
      .toList()
    ..shuffle();
  final _missedOnce = <int>{};
  var _shown = false;
  var _right = 0;
  var _wrong = 0;

  void _answer(bool gotIt) {
    final c = _queue.removeAt(0);
    if (gotIt) {
      Haptics.success();
    } else {
      Haptics.reject();
    }
    gotIt ? _right++ : _wrong++;
    final first = !_missedOnce.contains(c['id']);
    if (!widget.all && first) {
      final r = Recall.review((c['box'] as int?) ?? 0, gotIt, DateTime.now());
      c['box'] = r.box;
      c['due'] = r.due;
      widget.store.save();
    }
    if (!gotIt) {
      _missedOnce.add(c['id'] as int);
      _queue.add(c);
    }
    setState(() => _shown = false);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (_queue.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Done', style: tt.headlineMedium),
              const SizedBox(height: 8),
              Text('$_right right, $_wrong missed. Missed cards come back tomorrow.', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ]),
          ),
        ),
      );
    }
    final c = _queue.first;
    return Scaffold(
      appBar: AppBar(title: Text('${_queue.length} left')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${c['deck']}', style: tt.labelLarge?.copyWith(color: scheme.primary)),
          const SizedBox(height: 8),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${c['q']}', style: tt.headlineSmall),
                    if (_shown) ...[
                      const Divider(height: 32),
                      Text('${c['a']}', style: tt.titleLarge?.copyWith(color: scheme.primary)),
                    ],
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!_shown)
            FilledButton(
              onPressed: () => setState(() => _shown = true),
              child: const Padding(padding: EdgeInsets.all(12), child: Text('Show answer')),
            )
          else
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _answer(false),
                  child: const Padding(padding: EdgeInsets.all(12), child: Text('Missed it')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => _answer(true),
                  child: const Padding(padding: EdgeInsets.all(12), child: Text('Got it')),
                ),
              ),
            ]),
          if (!_shown)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Say or write the answer first, then check.', textAlign: TextAlign.center, style: tt.bodySmall),
            ),
        ]),
      ),
    );
  }
}
