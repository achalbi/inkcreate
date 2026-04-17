import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';

class LanguageIdentificationService {
  final LanguageIdentifier _identifier = LanguageIdentifier(
    confidenceThreshold: 0.25,
  );

  Future<Map<String, dynamic>> identify(String text) async {
    final String bestLanguageCode = await _identifier.identifyLanguage(text);
    final List<IdentifiedLanguage> candidates = await _identifier
        .identifyPossibleLanguages(text);

    return <String, dynamic>{
      'languageCode': bestLanguageCode,
      'bestLanguageCode': bestLanguageCode,
      'candidates': candidates
          .map(
            (IdentifiedLanguage candidate) => <String, dynamic>{
              'languageCode': candidate.languageTag,
              'confidence': candidate.confidence,
            },
          )
          .toList(growable: false),
    };
  }

  Future<void> close() => _identifier.close();
}
