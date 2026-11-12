import 'package:flutter/material.dart';

import 'focus_screen.dart';
import 'haptics.dart';
import 'items_screen.dart';
import 'pages.dart';
import 'plan_day_page.dart';
import 'productivity.dart';
import 'recall_page.dart';
import 'store.dart';
import 'task_sheet.dart';

const _boxNames = {3: 'Do first', 2: 'Schedule', 1: 'Delegate', 0: 'Eliminate'};

bool _isTask(Rec i) => i['kind'] == 'task' && i['status'] == 'open';
String _listOf(Rec i) => (i['list'] as String?) ?? 'Inbox';

void _push(BuildContext context, Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

void startDeepWork(BuildContext context, Store s, {int? taskId}) => _push(
      context,
      Scaffold(appBar: AppBar(title: const Text('Deep work')), body: FocusScreen(store: s, taskId: taskId, deep: true)),
    );

/// The six methods in the order you use them: clear your head, pick what matters, find what gives the most,
/// put it in the day, do it deeply, and learn what you need. Each step shows where you stand and opens its tool.
class EnginePage extends StatelessWidget {
  const EnginePage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final s = store;
          final now = DateTime.now();
          final tt = Theme.of(context).textTheme;
          final scheme = Theme.of(context).colorScheme;
          final items = s.list('items');
          final tasks = items.where(_isTask).toList();
          final active = tasks.where((i) => _listOf(i) != 'Waiting' && _listOf(i) != 'Someday').toList();
          int inList(String l) => tasks.where((i) => _listOf(i) == l).length;
          final top = Engine.topTask(items);

          // Time blocking: what already has a time today, and what still needs one.
          final tomorrow = DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
          final timed = active.where((i) => i['when'] is int && (i['when'] as int) < tomorrow && i['allDay'] != true).length;
          final unplaced = active.where((i) => i['when'] == null || ((i['when'] as int) < tomorrow && i['allDay'] == true)).length;

          final vital = active.where((i) => i['vital'] == true).length;
          final deep = Engine.deepMinutesThisWeek(s.list('focus'), now);
          final review = s.settings['gtdReview'] as int?;
          final suggestions = s.list('inbox').length;

          return Scaffold(
            appBar: AppBar(title: const Text('Productivity engine')),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  color: scheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Do this now', style: tt.labelLarge),
                      const SizedBox(height: 4),
                      if (top == null)
                        Text('Nothing waiting. Capture what is on your mind, then come back.', style: tt.titleMedium)
                      else ...[
                        Text('${top['title']}', style: tt.headlineSmall),
                        Text(
                          [
                            _boxNames[(top['priority'] as int?) ?? 0]!,
                            if (top['vital'] == true) 'vital',
                            if (top['when'] is int) niceWhen(top['when'] as int),
                          ].join('  ·  '),
                          style: tt.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, children: [
                          FilledButton.icon(
                            onPressed: () => startDeepWork(context, s, taskId: top['id'] as int),
                            icon: const Icon(Icons.center_focus_strong),
                            label: const Text('Start deep work'),
                          ),
                          TextButton(onPressed: () => showTaskSheet(context, s, item: top), child: const Text('Open task')),
                        ]),
                      ],
                    ]),
                  ),
                ),
                _Step(
                  n: 1,
                  title: 'Keep your mind clear',
                  method: 'Getting Things Done',
                  figure: inList('Inbox') == 0 && suggestions == 0 ? 'Inbox clear' : '${inList('Inbox') + suggestions} to sort',
                  detail: 'Next ${inList('Next')}  ·  Waiting ${inList('Waiting')}  ·  Someday ${inList('Someday')}\n'
                      '${Gtd.reviewDue(review, now) ? 'Weekly review is due' : 'Reviewed ${dayKey(fromMs(review!))}'}',
                  action: 'Sort and review',
                  onTap: () => _push(context, GtdPage(store: s)),
                ),
                _Step(
                  n: 2,
                  title: 'Decide what matters',
                  method: 'Eisenhower Matrix',
                  figure: '${active.where((i) => i['priority'] == 3).length} to do first',
                  detail: [for (final p in [2, 1, 0]) '${_boxNames[p]} ${active.where((i) => ((i['priority'] as int?) ?? 0) == p).length}'].join('  ·  '),
                  action: 'Open the matrix',
                  onTap: () => _push(context, MatrixPage(store: s)),
                ),
                _Step(
                  n: 3,
                  title: 'Find what gives the most',
                  method: 'Pareto principle (80/20)',
                  figure: '$vital vital',
                  detail: 'Of ${active.length} open tasks, aim for about ${Pareto.target(active.length)}: the few that bring most of the results.',
                  action: 'Pick the vital few',
                  onTap: () => _push(context, ParetoPage(store: s)),
                ),
                _Step(
                  n: 4,
                  title: 'Decide when to work',
                  method: 'Time blocking',
                  figure: '$timed blocked today',
                  detail: unplaced == 0 ? 'Every task has a time.' : '$unplaced without a time yet.',
                  action: 'Plan my day',
                  onTap: () => _push(context, PlanDayPage(store: s)),
                ),
                _Step(
                  n: 5,
                  title: 'Work deeply',
                  method: 'Deep work',
                  figure: '${deep ~/ 60}h ${deep % 60}m this week',
                  detail: 'One task, a long block, no switching.',
                  action: 'Start a block',
                  onTap: () => startDeepWork(context, s, taskId: top?['id'] as int?),
                ),
                _Step(
                  n: 6,
                  title: 'Learn faster',
                  method: 'Active recall',
                  figure: '${dueCards(s)} cards due',
                  detail: '${s.list('cards').length} cards in ${recallDecks(s).length} decks. Answer from memory, then check.',
                  action: 'Review cards',
                  onTap: () => _push(context, RecallPage(store: s)),
                ),
              ],
            ),
          );
        },
      );
}

class _Step extends StatelessWidget {
  const _Step({
    required this.n,
    required this.title,
    required this.method,
    required this.figure,
    required this.detail,
    required this.action,
    required this.onTap,
  });
  final int n;
  final String title, method, figure, detail, action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 14, child: Text('$n', style: tt.labelLarge)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: tt.titleMedium),
                Text(method, style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Text(figure, style: tt.titleLarge?.copyWith(color: scheme.primary)),
                Text(detail, style: tt.bodySmall),
                const SizedBox(height: 4),
                Text(action, style: tt.labelLarge?.copyWith(color: scheme.primary)),
              ]),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

/// Mark the vital few: the tasks that bring most of the results.
class ParetoPage extends StatelessWidget {
  const ParetoPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final s = store;
          final tt = Theme.of(context).textTheme;
          final scheme = Theme.of(context).colorScheme;
          final open = s.list('items').where((i) => _isTask(i) && _listOf(i) != 'Someday').toList()
            ..sort((a, b) => ((b['priority'] as int?) ?? 0).compareTo((a['priority'] as int?) ?? 0));
          final vital = open.where((i) => i['vital'] == true).toList();
          final rest = open.where((i) => i['vital'] != true).toList();
          final target = Pareto.target(open.length);
          Widget row(Rec it) => Card(
                child: ListTile(
                  leading: IconButton(
                    tooltip: it['vital'] == true ? 'Not vital' : 'Vital',
                    icon: Icon(it['vital'] == true ? Icons.star : Icons.star_border, color: it['vital'] == true ? scheme.tertiary : null),
                    onPressed: () {
                      Haptics.toggle(it['vital'] != true);
                      s.updateRec('items', it, '${it['title']}: ${it['vital'] == true ? 'not vital' : 'vital'}', (r) => r['vital'] = r['vital'] != true);
                    },
                  ),
                  title: Text('${it['title']}'),
                  subtitle: Text(_boxNames[(it['priority'] as int?) ?? 0]!),
                  onTap: () => showTaskSheet(context, s, item: it),
                ),
              );
          return Scaffold(
            appBar: AppBar(title: const Text('The vital few')),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text('${vital.length} of about $target', style: tt.headlineSmall),
                Text(
                  'Ask of each task: if I did only this today, would it move things most? Star those. '
                  'Vital tasks go first in the matrix, the day plan and "Do this now".',
                  style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (vital.length > target && target > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('That is more than one in five. Keep only the ones that truly matter most.', style: tt.bodySmall?.copyWith(color: scheme.error)),
                  ),
                const SizedBox(height: 12),
                if (open.isEmpty) const Text('No open tasks.'),
                for (final it in vital) row(it),
                if (vital.isNotEmpty && rest.isNotEmpty) const Divider(height: 24),
                for (final it in rest) row(it),
              ],
            ),
          );
        },
      );
}

/// GTD: sort what was captured into Next, Waiting or Someday, look over what is parked, and mark the weekly review.
class GtdPage extends StatelessWidget {
  const GtdPage({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final s = store;
          final now = DateTime.now();
          final tt = Theme.of(context).textTheme;
          final scheme = Theme.of(context).colorScheme;
          final tasks = s.list('items').where(_isTask).toList();
          List<Rec> inList(String l) => tasks.where((i) => _listOf(i) == l).toList();
          final review = s.settings['gtdReview'] as int?;
          final suggestions = s.list('inbox').length;

          void move(Rec it, String l) {
            Haptics.tap();
            s.updateRec('items', it, 'Moved ${it['title']} to $l', (r) => r['list'] = l);
          }

          Widget row(Rec it, List<String> to) => Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    InkWell(onTap: () => showTaskSheet(context, s, item: it), child: Text('${it['title']}', style: tt.titleSmall)),
                    Wrap(spacing: 4, children: [
                      for (final l in to) TextButton(onPressed: () => move(it, l), child: Text(l == 'Next' ? 'Next action' : l)),
                      TextButton(
                        onPressed: () {
                          Haptics.success();
                          s.markDone(it);
                        },
                        child: const Text('Done'),
                      ),
                    ]),
                  ]),
                ),
              );

          Widget heading(String text, String sub) => Padding(
                padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(text, style: tt.titleMedium?.copyWith(color: scheme.primary)),
                  Text(sub, style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ]),
              );

          final inbox = inList('Inbox');
          final waiting = inList('Waiting');
          final someday = inList('Someday');
          return Scaffold(
            appBar: AppBar(title: const Text('Mind clear')),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(Gtd.reviewDue(review, now) ? 'Weekly review is due' : 'Reviewed ${dayKey(fromMs(review!))}', style: tt.headlineSmall),
                Text(
                  'Once a week: empty the inbox, check what you are waiting for, look over someday, then pick the vital few.',
                  style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Haptics.success();
                    s.settings['gtdReview'] = now.millisecondsSinceEpoch;
                    s.save();
                  },
                  icon: const Icon(Icons.task_alt),
                  label: const Text('Finish weekly review'),
                ),
                if (suggestions > 0) ...[
                  heading('From Jarvis', 'Things Jarvis heard but wants you to confirm.'),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.inbox_outlined),
                      title: Text('$suggestions to confirm'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _push(context, InboxPage(store: s)),
                    ),
                  ),
                ],
                heading('Inbox (${inbox.length})', 'Captured, not yet decided. What is the next step, and is it yours?'),
                if (inbox.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Empty. Nice.')),
                for (final it in inbox) row(it, const ['Next', 'Waiting', 'Someday']),
                heading('Waiting for (${waiting.length})', 'Someone else has the next step. Chase it, or bring it back.'),
                for (final it in waiting) row(it, const ['Next', 'Someday']),
                heading('Someday, maybe (${someday.length})', 'Not now. Bring back anything whose time has come.'),
                for (final it in someday) row(it, const ['Next']),
                heading('Next actions (${inList('Next').length})', 'Ready to do. Rank them in the matrix.'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: () => _push(context, MatrixPage(store: s)), child: const Text('Open the matrix')),
                ),
              ],
            ),
          );
        },
      );
}
