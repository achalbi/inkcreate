import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/native_bridge_models.dart';
import '../../../core/services/platform_bridge_service.dart';
import '../entity_extraction/entity_extraction_service.dart';
import '../language_identification/language_identification_service.dart';
import '../translation/translation_service.dart';
import '../../native_genai/prompt/prompt_service.dart';
import '../../native_genai/summarization/summarization_service.dart';

class DocumentScannerPage extends StatefulWidget {
  const DocumentScannerPage({
    super.key,
    required this.requestId,
    required this.route,
    required this.payload,
    required this.platformBridgeService,
    required this.languageIdentificationService,
    required this.translationService,
    required this.entityExtractionService,
    required this.summarizationService,
    required this.promptService,
  });

  final String requestId;
  final String route;
  final Map<String, dynamic> payload;
  final PlatformBridgeService platformBridgeService;
  final LanguageIdentificationService languageIdentificationService;
  final TranslationService translationService;
  final EntityExtractionService entityExtractionService;
  final SummarizationService summarizationService;
  final PromptService promptService;

  @override
  State<DocumentScannerPage> createState() => _DocumentScannerPageState();
}

class _DocumentScannerPageState extends State<DocumentScannerPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    try {
      final Map<String, dynamic> scannerResult = await widget
          .platformBridgeService
          .scanDocument(<String, dynamic>{
            'requestId': widget.requestId,
            ...widget.payload,
          });

      if (!mounted) {
        return;
      }

      if (scannerResult['cancelled'] == true) {
        Navigator.of(context).pop(
          NativeRouteResult.cancelled(
            requestId: widget.requestId,
            route: widget.route,
          ),
        );
        return;
      }

      final String fullText =
          scannerResult['analysis']?['ocr']?['fullText']?.toString() ?? '';
      final Map<String, dynamic> analysis = Map<String, dynamic>.from(
        (scannerResult['analysis'] as Map?) ?? const <String, dynamic>{},
      );

      if (fullText.isNotEmpty) {
        final Map<String, dynamic> language = await widget
            .languageIdentificationService
            .identify(fullText);
        analysis['languageIdentification'] = language;

        if (widget.payload['translateTo'] != null &&
            widget.payload['translateTo'] != language['languageCode']) {
          // The route contract is ready for translation chaining; the concrete language mapping
          // should be finalized against the web payload vocabulary.
          analysis['translation'] = <String, dynamic>{
            'status': 'skipped',
            'reason': 'PAYLOAD_LANGUAGE_MAPPING_REQUIRED',
          };
        }

        analysis['entityExtraction'] = <String, dynamic>{
          'status': 'deferred',
          'reason': 'LANGUAGE_MODEL_MAPPING_REQUIRED',
        };
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(
        NativeRouteResult.success(
          requestId: widget.requestId,
          route: widget.route,
          data: <String, dynamic>{
            'scanner': scannerResult['scanner'] ?? scannerResult,
            'analysis': analysis,
          },
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      if (error is PlatformException) {
        Navigator.of(context).pop(
          NativeRouteResult.unavailable(
            requestId: widget.requestId,
            route: widget.route,
            code: error.code,
            message: error.message ?? error.toString(),
          ),
        );
        return;
      }

      Navigator.of(context).pop(
        NativeRouteResult.error(
          requestId: widget.requestId,
          route: widget.route,
          code: NativeErrorCode.featureUnavailable,
          message: error.toString(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
