import 'package:flutter_test/flutter_test.dart';
import 'package:jarcis/web.dart';

void main() {
  test('spots a request to search', () {
    expect(Web.asked('search for Dhaka weather tomorrow'), 'Dhaka weather tomorrow');
    expect(Web.asked('Hey Jarvis, google who won the BPL final'), 'who won the BPL final');
    expect(Web.asked('look up the iPhone 18 price in Bangladesh'), 'the iPhone 18 price in Bangladesh');
    expect(Web.asked('search the web for gold price today?'), 'gold price today');
    expect(Web.asked('find online cheap flights to Cox\'s Bazar'), 'cheap flights to Cox\'s Bazar');
  });

  test('ordinary notes are not searches', () {
    expect(Web.asked('call Ammu at 8 pm'), null);
    expect(Web.asked('I need to research the market for my report'), null);
    expect(Web.asked('search'), null);
    expect(Web.asked('what is the weather today'), null); // the AI decides this one
  });

  test('reads a Gemini Google Search answer', () {
    final a = Web.parseGemini({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': 'It will rain in Dhaka tomorrow.'},
            ],
          },
          'groundingMetadata': {
            'groundingChunks': [
              {'web': {'uri': 'https://a.example/1', 'title': 'weather.com'}},
              {'web': {'uri': 'https://a.example/1', 'title': 'weather.com'}},
              {'web': {'uri': 'https://b.example/2', 'title': 'bmd.gov.bd'}},
            ],
          },
        },
      ],
    });
    expect(a.text, 'It will rain in Dhaka tomorrow.');
    expect(a.sources.map((x) => x.title), ['weather.com', 'bmd.gov.bd']);
  });

  test('reads a Groq answer and moves links out of the text', () {
    final a = Web.parseOpenAi({
      'choices': [
        {
          'message': {
            'content': '<think>hmm</think>**Bangladesh** won by 5 wickets '
                '([ESPNcricinfo](https://www.espncricinfo.com/match/1)). More: https://www.bbc.com/sport/x.'
          },
        },
      ],
    });
    expect(a.text, 'Bangladesh won by 5 wickets (ESPNcricinfo). More:');
    expect(a.sources.map((x) => x.title), ['www.espncricinfo.com', 'www.bbc.com']);
  });

  test('citation markers from the search model are removed', () {
    final a = Web.parseOpenAi({
      'choices': [
        {
          'message': {'content': 'Real Madrid won 3-0 at Valencia on 8 Nov 2026, with goals from Valverde and Mbapp\u00e9\u30103\u2020L5-L11\u3011. They play again on Wednesday.\u30104\u2020L2-L4\u3011'}
        }
      ]
    });
    expect(a.text, 'Real Madrid won 3-0 at Valencia on 8 Nov 2026, with goals from Valverde and Mbapp\u00e9. They play again on Wednesday.');
  });
}
