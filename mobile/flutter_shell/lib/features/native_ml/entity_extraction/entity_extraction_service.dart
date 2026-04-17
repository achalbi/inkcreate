import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';

class EntityExtractionService {
  Future<Map<String, dynamic>> extract({
    required String text,
    required EntityExtractorLanguage language,
  }) async {
    final EntityExtractor extractor = EntityExtractor(language: language);
    final EntityExtractorModelManager manager = EntityExtractorModelManager();
    final bool downloaded = await manager.isModelDownloaded(language.name);

    if (!downloaded) {
      await manager.downloadModel(language.name);
    }

    final List<EntityAnnotation> annotations;
    try {
      annotations = await extractor.annotateText(text);
    } finally {
      await extractor.close();
    }

    return <String, dynamic>{
      'language': language.name,
      'entities': annotations
          .map(
            (EntityAnnotation annotation) => <String, dynamic>{
              'text': annotation.text,
              'start': annotation.start,
              'end': annotation.end,
              'entities': annotation.entities
                  .map(
                    (Entity entity) => <String, dynamic>{
                      'type': entity.type.name,
                      'rawValue': entity.rawValue,
                    },
                  )
                  .toList(growable: false),
            },
          )
          .toList(growable: false),
    };
  }
}
