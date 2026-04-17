import 'dart:async';

import 'package:flutter/services.dart';

import '../models/native_bridge_models.dart';

class PlatformBridgeService {
  static const MethodChannel _documentScannerChannel = MethodChannel(
    'com.inkcreate.mobile/document_scanner',
  );
  static const MethodChannel _genAiChannel = MethodChannel(
    'com.inkcreate.mobile/genai',
  );
  static const EventChannel _genAiProgressChannel = EventChannel(
    'com.inkcreate.mobile/genai_progress',
  );

  Stream<NativeProgressEvent>? _progressStream;

  Stream<NativeProgressEvent> progressEvents() {
    return _progressStream ??= _genAiProgressChannel
        .receiveBroadcastStream()
        .map((dynamic event) {
          final Map<Object?, Object?> raw =
              (event as Map<Object?, Object?>?) ?? const <Object?, Object?>{};
          return NativeProgressEvent(
            requestId: raw['requestId']?.toString() ?? '',
            route: raw['route']?.toString() ?? '',
            status: raw['status']?.toString() ?? '',
            progress: (raw['progress'] as num?)?.toDouble(),
            partialData: Map<String, dynamic>.from(
              (raw['partialData'] as Map?) ?? const <String, dynamic>{},
            ),
          );
        });
  }

  Future<Map<String, dynamic>> scanDocument(
    Map<String, dynamic> payload,
  ) async {
    final dynamic response = await _documentScannerChannel
        .invokeMethod<dynamic>('scanDocument', payload);
    return Map<String, dynamic>.from(
      (response as Map?) ?? const <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> fetchGenAiCapabilities() async {
    final dynamic response = await _genAiChannel.invokeMethod<dynamic>(
      'getCapabilities',
    );
    return Map<String, dynamic>.from(
      (response as Map?) ?? const <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> runSummarization(
    Map<String, dynamic> payload,
  ) async {
    final dynamic response = await _genAiChannel.invokeMethod<dynamic>(
      'runSummarization',
      payload,
    );
    return Map<String, dynamic>.from(
      (response as Map?) ?? const <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> runPrompt(Map<String, dynamic> payload) async {
    final dynamic response = await _genAiChannel.invokeMethod<dynamic>(
      'runPrompt',
      payload,
    );
    return Map<String, dynamic>.from(
      (response as Map?) ?? const <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> startSpeechRecognition(
    Map<String, dynamic> payload,
  ) async {
    final dynamic response = await _genAiChannel.invokeMethod<dynamic>(
      'startSpeechRecognition',
      payload,
    );
    return Map<String, dynamic>.from(
      (response as Map?) ?? const <String, dynamic>{},
    );
  }

  Future<void> cancelSpeechRecognition() async {
    await _genAiChannel.invokeMethod<void>('cancelSpeechRecognition');
  }
}
