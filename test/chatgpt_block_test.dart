import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/chatgpt_block.dart';

void main() {
  test('reads a block inside a code fence, items are sure by default', () {
    const raw = '''Here you go:
```
JARVIS v1
{"reply": "Done.", "remember": ["Oishi is my sister"],
 "items": [{"type": "task", "title": "Tell Oishi to come", "date": "2026-11-13", "time": null},
           {"type": "alarm", "title": "Tell Oishi", "date": "2026-11-10", "time": "20:00", "confidence": 0.5}]}
```''';
    final b = ChatGptBlock.parse(raw)!;
    expect(b['reply'], 'Done.');
    expect(b['remember'], ['Oishi is my sister']);
    expect((b['items'] as List).length, 2);
    expect((b['items'] as List)[0]['confidence'], 1);
    expect((b['items'] as List)[1]['confidence'], 0.5);
  });

  test('ordinary notes have no block', () {
    expect(ChatGptBlock.has('remind me to call Jarvis later'), isFalse);
    expect(ChatGptBlock.parse('buy milk'), isNull);
  });

  test('broken blocks say why', () {
    expect(() => ChatGptBlock.parse('JARVIS v1 nothing here'), throwsFormatException);
    expect(() => ChatGptBlock.parse('JARVIS v1 {"items": 3}'), throwsFormatException);
    expect(() => ChatGptBlock.parse('JARVIS v2 {"items": []}'), throwsFormatException);
  });
}
