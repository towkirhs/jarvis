import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/drive_search.dart';

void main() {
  test('chunks cut at paragraph ends and cover all the text', () {
    final text = List.generate(30, (i) => 'Paragraph $i has some words in it about topic $i.').join('\n\n');
    final chunks = DriveSearch.chunk(text, size: 300);
    expect(chunks.length, greaterThan(3));
    expect(chunks.every((c) => c.length <= 300), isTrue);
    expect(chunks.first.startsWith('Paragraph 0'), isTrue);
    expect(chunks.last.endsWith('topic 29.'), isTrue);
  });

  test('empty text has no chunks', () {
    expect(DriveSearch.chunk('  \n\n '), isEmpty);
  });

  test('the passage with the rarer matching words wins', () {
    final files = [
      ['The tenant must give one month notice before leaving the room.', 'Rent is due on the 5th of every month.'],
      ['Enzymes lower activation energy. Michaelis Menten kinetics describe enzyme speed.'],
    ];
    final hits = DriveSearch.search('How much notice must the tenant give?', files);
    expect((hits.first.$1, hits.first.$2), (0, 0));
    final bio = DriveSearch.search('michaelis menten', files);
    expect((bio.single.$1, bio.single.$2), (1, 0));
  });

  test('words: lower case, no stop words, Bangla kept', () {
    expect(DriveSearch.words('What is the RENT for ঘর ৩?'), ['rent', 'ঘর']);
  });
}
