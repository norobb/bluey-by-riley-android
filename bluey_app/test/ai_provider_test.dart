import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bluey_app/ai/ai_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Gemini Model Configuration Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('GeminiProvider defaults to gemini-3.7-flash for general tasks', () {
      final provider = GeminiProvider();
      expect(provider.selectedGeneralModel, equals(GeneralGeminiModel.gemini37Flash));
      expect(provider.selectedGeneralModel.modelId, equals('gemini-3.7-flash'));
    });

    test('GeminiProvider allows switching to gemini-3.8-flash and persisting setting', () async {
      final provider = GeminiProvider();
      await provider.setSelectedModel(GeneralGeminiModel.gemini38Flash);

      expect(provider.selectedGeneralModel, equals(GeneralGeminiModel.gemini38Flash));
      expect(provider.selectedGeneralModel.modelId, equals('gemini-3.8-flash'));

      final reloaded = GeminiProvider();
      await reloaded.loadSelectedModel();
      expect(reloaded.selectedGeneralModel, equals(GeneralGeminiModel.gemini38Flash));
    });

    test('GeminiProvider uses separate model role for Realtime Live API', () {
      expect(GeminiProvider.realtimeModelId, equals('models/gemini-2.0-flash-exp'));
    });
  });
}
