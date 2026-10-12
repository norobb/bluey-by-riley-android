import 'package:flutter_test/flutter_test.dart';
import 'package:bluey_app/ai/ai_provider.dart';

void main() {
  group('AI Provider Tests', () {
    test('GeminiProvider name and instantiation', () {
      final gemini = GeminiProvider();
      expect(gemini.name, equals('Google Gemini'));
    });

    test('OpenAIProvider name and instantiation', () {
      final openai = OpenAIProvider();
      expect(openai.name, equals('OpenAI'));
    });

    test('GeminiRealtimeSession frame structure formatting', () {
      final gemini = GeminiProvider();
      final session = gemini.createRealtimeSession(
        apiKey: 'test_key',
        systemInstruction: 'You are Bluey.',
        tools: [
          {
            'name': 'look_at_screen',
            'description': 'Take a look at screen.',
            'parameters': {'type': 'object'}
          }
        ],
      );

      expect(session, isA<GeminiRealtimeSession>());
      session.close();
    });
  });
}
