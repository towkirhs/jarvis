import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/about_me.dart';

void main() {
  final words = <Map<String, dynamic>>[
    {'from': 'jarbis', 'to': 'Jarvis'},
    {'from': 'dua ris', 'to': 'Duaris'},
    {'from': 'oishee', 'to': 'Oishi'},
  ];

  test('your words fix what the phone heard, whole words only, any case', () {
    expect(Words.fix('Hey Jarbis, buy dua  ris cream for Oishee', words), 'Hey Jarvis, buy Duaris cream for Oishi');
    expect(Words.fix('jarbisx stays', words), 'jarbisx stays');
  });

  test('an edit that changes a few words is offered as a new word', () {
    expect(Words.change('buy dua ris cream', 'buy Duaris cream'), ('dua ris', 'Duaris'));
    expect(Words.change('call oishee now.', 'call Oishi now.'), ('oishee', 'Oishi'));
    expect(Words.change('spent 200 on lunch', 'spent 250 on lunch at the office canteen today'), isNull);
    expect(Words.change('same text', 'same text'), isNull);
    expect(Words.change('Hello', 'hello'), isNull);
  });

  test('profile files: always-used ones, then those whose key words are in the note, within the size limit', () {
    final files = <Map<String, dynamic>>[
      {'name': 'How I talk', 'always': true, 'text': 'I say "clear it" for done.'},
      {'name': 'Money', 'keys': ['bkash', 'rent', 'taka'], 'text': 'Cash is my main account.'},
      {'name': 'Study', 'keys': ['exam', 'class test'], 'text': 'Physics on Sundays.'},
      {'name': 'Huge', 'keys': ['rent'], 'text': 'x' * 5000},
    ];
    List<String> names(String note) => ProfileFiles.pick(files, note).map((f) => '${f['name']}').toList();
    expect(names('sent 500 by bKash'), ['How I talk', 'Money']);
    expect(names('class test tomorrow'), ['How I talk', 'Study']);
    expect(names('rent paid'), ['How I talk', 'Money']); // the huge file does not fit
    expect(names('classes tomorrow'), ['How I talk']);
  });

  test('a ChatGPT profile item becomes a file; one with no text is refused', () {
    expect(ProfileFiles.fromBlock({'type': 'profile', 'title': 'Routines', 'keys': ['gym', ' '], 'text': 'Gym at 6.'}),
        {'name': 'Routines', 'keys': ['gym'], 'always': false, 'text': 'Gym at 6.'});
    expect(ProfileFiles.fromBlock({'type': 'profile', 'title': 'Empty'}), isNull);
  });
}
