import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class TranslationService {
  Future<Map<String, dynamic>> translate({
    required String text,
    required TranslateLanguage sourceLanguage,
    required TranslateLanguage targetLanguage,
  }) async {
    final OnDeviceTranslator translator = OnDeviceTranslator(
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
    final OnDeviceTranslatorModelManager modelManager =
        OnDeviceTranslatorModelManager();

    final bool sourceDownloaded = await modelManager.isModelDownloaded(
      sourceLanguage.bcpCode,
    );
    final bool targetDownloaded = await modelManager.isModelDownloaded(
      targetLanguage.bcpCode,
    );

    if (!sourceDownloaded) {
      await modelManager.downloadModel(sourceLanguage.bcpCode);
    }

    if (!targetDownloaded) {
      await modelManager.downloadModel(targetLanguage.bcpCode);
    }

    final String translatedText = await translator.translateText(text);
    await translator.close();

    return <String, dynamic>{
      'translatedText': translatedText,
      'sourceLanguage': sourceLanguage.bcpCode,
      'targetLanguage': targetLanguage.bcpCode,
      'modelStatus': <String, dynamic>{
        'sourceDownloaded': true,
        'targetDownloaded': true,
      },
    };
  }
}
