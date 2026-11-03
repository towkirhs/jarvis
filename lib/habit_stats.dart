import 'store.dart';

/// Colours a habit can have (ARGB). A habit stores an index into this list.
const habitColors = [
  0xFF64B5F6, 0xFFB39DDB, 0xFFF48FB1, 0xFFFFF59D,
  0xFF81C784, 0xFFFFB74D, 0xFF4DD0E1, 0xFFE57373,
];

int habitColor(Rec h) => habitColors[((h['color'] as int?) ?? 0) % habitColors.length];

String habitTarget(Rec h) => '${h['times']} times per ${h['per']}';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

bool _done(Rec h, DateTime d) => (h['logs'] as Rec)[dayKey(d)] == 'yes';

/// Share of the target reached over the 30 days ending on asOf, from 0 to 1.
double habitScore(Rec h, DateTime asOf) {
  final end = _day(asOf);
  var done = 0;
  for (var i = 0; i < 30; i++) {
    if (_done(h, DateTime(end.year, end.month, end.day - i))) done++;
  }
  final times = (h['times'] as num).toDouble();
  final expected = h['per'] == 'month' ? times : times * 30 / 7;
  if (expected <= 0) return 0;
  return (done / expected).clamp(0.0, 1.0);
}

int habitTotal(Rec h) => (h['logs'] as Rec).values.where((v) => v == 'yes').length;

/// First day of each of the last n months, oldest first.
List<DateTime> lastMonths(int n) {
  final now = DateTime.now();
  return [for (var i = n - 1; i >= 0; i--) DateTime(now.year, now.month - i, 1)];
}

/// Times done in each of the last n months, oldest first.
List<int> monthCounts(Rec h, int n) => [
      for (final m in lastMonths(n))
        (h['logs'] as Rec)
            .entries
            .where((e) => e.value == 'yes' && e.key.startsWith('${m.year}-${two(m.month)}'))
            .length,
    ];

/// Score at the end of each of the last n months (today for the current one), oldest first.
List<double> monthScores(Rec h, int n) {
  final today = _day(DateTime.now());
  return [
    for (final m in lastMonths(n))
      habitScore(h, () {
        final end = DateTime(m.year, m.month + 1, 0);
        return end.isAfter(today) ? today : end;
      }()),
  ];
}

class Streak {
  Streak(this.start, this.end);
  final DateTime start;
  final DateTime end;
  int get length => end.difference(start).inDays + 1;
}

/// The n longest runs of consecutive done days, newest first.
List<Streak> bestStreaks(Rec h, int n) {
  final days = (h['logs'] as Rec)
      .entries
      .where((e) => e.value == 'yes')
      .map((e) => DateTime.parse(e.key))
      .toList()
    ..sort();
  final runs = <Streak>[];
  for (final d in days) {
    if (runs.isNotEmpty && d.difference(runs.last.end).inDays == 1) {
      runs.last = Streak(runs.last.start, d);
    } else {
      runs.add(Streak(d, d));
    }
  }
  runs.sort((a, b) => b.length.compareTo(a.length));
  final top = runs.take(n).toList()..sort((a, b) => b.start.compareTo(a.start));
  return top;
}

/// Times done on each weekday, Monday first.
List<int> weekdayCounts(Rec h) {
  final c = List.filled(7, 0);
  for (final e in (h['logs'] as Rec).entries) {
    if (e.value == 'yes') c[DateTime.parse(e.key).weekday - 1]++;
  }
  return c;
}
