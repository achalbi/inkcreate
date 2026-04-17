import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../models/native_bridge_models.dart';
import 'platform_bridge_service.dart';
import '../../features/native_genai/prompt/prompt_service.dart';
import '../../features/native_genai/speech_recognition/speech_recognition_page.dart';
import '../../features/native_genai/summarization/summarization_service.dart';
import '../../features/native_ml/barcode_scanning/barcode_scanning_page.dart';
import '../../features/native_ml/document_scanner/document_scanner_page.dart';
import '../../features/native_ml/entity_extraction/entity_extraction_service.dart';
import '../../features/native_ml/language_identification/language_identification_service.dart';
import '../../features/native_ml/text_recognition_v2/text_recognition_v2_page.dart';
import '../../features/native_ml/translation/translation_service.dart';
import '../../features/web_shell/native_capabilities_service.dart';

class NativeRouteExecutor {
  NativeRouteExecutor({
    required this.navigatorKey,
    required this.capabilitiesService,
    required this.platformBridgeService,
    required this.languageIdentificationService,
    required this.translationService,
    required this.entityExtractionService,
    required this.summarizationService,
    required this.promptService,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final NativeCapabilitiesService capabilitiesService;
  final PlatformBridgeService platformBridgeService;
  final LanguageIdentificationService languageIdentificationService;
  final TranslationService translationService;
  final EntityExtractionService entityExtractionService;
  final SummarizationService summarizationService;
  final PromptService promptService;

  Future<NativeRouteResult> execute(
    NativeRouteRequest request, {
    NativeProgressCallback? onProgress,
  }) async {
    await capabilitiesService.refresh();

    final String route = request.route ?? '';
    final NativeRouteCapability capability = capabilitiesService.capabilityFor(
      route,
    );
    if (!capability.supported) {
      return NativeRouteResult.unavailable(
        requestId: request.requestId,
        route: route,
        code: capability.reason ?? NativeErrorCode.featureUnavailable,
        message: 'Native route $route is unavailable on this device.',
      );
    }

    try {
      switch (route) {
        case 'mlkit:text-recognition-v2':
          return _pushNativeRouteResult(
            TextRecognitionV2Page(
              requestId: request.requestId,
              route: route,
              payload: request.payload,
            ),
            requestId: request.requestId,
            route: route,
          );
        case 'mlkit:barcode-scanning':
          return _pushNativeRouteResult(
            BarcodeScanningPage(requestId: request.requestId, route: route),
            requestId: request.requestId,
            route: route,
          );
        case 'mlkit:document-scanner':
          return _pushNativeRouteResult(
            DocumentScannerPage(
              requestId: request.requestId,
              route: route,
              payload: request.payload,
              platformBridgeService: platformBridgeService,
              languageIdentificationService: languageIdentificationService,
              translationService: translationService,
              entityExtractionService: entityExtractionService,
              summarizationService: summarizationService,
              promptService: promptService,
            ),
            requestId: request.requestId,
            route: route,
          );
        case 'genai:speech-recognition':
          return _pushNativeRouteResult(
            SpeechRecognitionPage(
              requestId: request.requestId,
              route: route,
              payload: request.payload,
              platformBridgeService: platformBridgeService,
            ),
            requestId: request.requestId,
            route: route,
          );
        case 'mlkit:language-identification':
          return _identifyLanguage(request);
        case 'mlkit:translation':
          return _translate(request);
        case 'mlkit:entity-extraction':
          return _extractEntities(request);
        case 'genai:summarization':
          return _summarize(request);
        case 'genai:prompt':
          return _prompt(request);
        default:
          return NativeRouteResult.unavailable(
            requestId: request.requestId,
            route: route,
            code: NativeErrorCode.featureUnavailable,
            message: 'Unknown native route: $route',
          );
      }
    } catch (error) {
      if (error is PlatformException) {
        final String code = error.code;
        final String message = error.message ?? error.toString();
        const Set<String> unavailableCodes = <String>{
          NativeErrorCode.androidOnly,
          NativeErrorCode.featureUnavailable,
          NativeErrorCode.deviceNotSupported,
          NativeErrorCode.aiCoreUnavailable,
          NativeErrorCode.modelDownloadRequired,
          NativeErrorCode.modelDownloading,
          NativeErrorCode.backgroundUseBlocked,
          NativeErrorCode.osVersionTooLow,
          NativeErrorCode.bootloaderUnlocked,
          NativeErrorCode.integrationNotFinalized,
          NativeErrorCode.cameraPermissionDenied,
          NativeErrorCode.microphonePermissionDenied,
        };

        if (unavailableCodes.contains(code)) {
          return NativeRouteResult.unavailable(
            requestId: request.requestId,
            route: route,
            code: code,
            message: message,
          );
        }

        return NativeRouteResult.error(
          requestId: request.requestId,
          route: route,
          code: code,
          message: message,
        );
      }

      return NativeRouteResult.error(
        requestId: request.requestId,
        route: route,
        code: NativeErrorCode.featureUnavailable,
        message: error.toString(),
      );
    }
  }

  Future<NativeRouteResult> _identifyLanguage(
    NativeRouteRequest request,
  ) async {
    final String text = request.payload['text']?.toString() ?? '';
    final Map<String, dynamic> result = await languageIdentificationService
        .identify(text);
    return NativeRouteResult.success(
      requestId: request.requestId,
      route: request.route ?? '',
      data: result,
    );
  }

  Future<NativeRouteResult> _translate(NativeRouteRequest request) async {
    final String text = request.payload['text']?.toString() ?? '';
    final TranslateLanguage source =
        _translateLanguageFromCode(
          request.payload['sourceLanguage']?.toString(),
        ) ??
        TranslateLanguage.english;
    final TranslateLanguage target =
        _translateLanguageFromCode(
          request.payload['targetLanguage']?.toString(),
        ) ??
        TranslateLanguage.english;

    final Map<String, dynamic> result = await translationService.translate(
      text: text,
      sourceLanguage: source,
      targetLanguage: target,
    );

    return NativeRouteResult.success(
      requestId: request.requestId,
      route: request.route ?? '',
      data: result,
    );
  }

  Future<NativeRouteResult> _extractEntities(NativeRouteRequest request) async {
    final String text = request.payload['text']?.toString() ?? '';
    final Map<String, dynamic> result = await entityExtractionService.extract(
      text: text,
      language: EntityExtractorLanguage.english,
    );
    return NativeRouteResult.success(
      requestId: request.requestId,
      route: request.route ?? '',
      data: result,
    );
  }

  Future<NativeRouteResult> _summarize(NativeRouteRequest request) async {
    if (!Platform.isAndroid) {
      return NativeRouteResult.unavailable(
        requestId: request.requestId,
        route: request.route ?? '',
        code: NativeErrorCode.androidOnly,
        message: 'Summarization is Android-only.',
      );
    }

    final Map<String, dynamic> result = await summarizationService.summarize(
      requestId: request.requestId,
      payload: request.payload,
    );
    return NativeRouteResult.success(
      requestId: request.requestId,
      route: request.route ?? '',
      data: result,
    );
  }

  Future<NativeRouteResult> _prompt(NativeRouteRequest request) async {
    if (!Platform.isAndroid) {
      return NativeRouteResult.unavailable(
        requestId: request.requestId,
        route: request.route ?? '',
        code: NativeErrorCode.androidOnly,
        message: 'Prompt API is Android-only.',
      );
    }

    final Map<String, dynamic> result = await promptService.runPrompt(
      requestId: request.requestId,
      payload: request.payload,
    );
    return NativeRouteResult.success(
      requestId: request.requestId,
      route: request.route ?? '',
      data: result,
    );
  }

  Future<T?> _pushRoute<T>(Widget page) {
    final NavigatorState? navigator = navigatorKey.currentState;
    if (navigator == null) {
      return Future<T?>.value();
    }

    return navigator.push<T>(
      MaterialPageRoute<T>(
        builder: (BuildContext context) => page,
        fullscreenDialog: true,
      ),
    );
  }

  Future<NativeRouteResult> _pushNativeRouteResult(
    Widget page, {
    required String requestId,
    required String route,
  }) async {
    final NativeRouteResult? result = await _pushRoute<NativeRouteResult>(page);
    return result ??
        NativeRouteResult.cancelled(requestId: requestId, route: route);
  }

  TranslateLanguage? _translateLanguageFromCode(String? code) {
    if (code == null || code.isEmpty) {
      return null;
    }

    return TranslateLanguage.values.cast<TranslateLanguage?>().firstWhere(
      (TranslateLanguage? language) => language?.bcpCode == code,
      orElse: () => null,
    );
  }
}
