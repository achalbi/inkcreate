import 'dart:io';

import 'package:flutter/services.dart';

import '../../../core/models/native_bridge_models.dart';
import '../../../core/services/app_lifecycle_service.dart';
import '../../../core/services/platform_bridge_service.dart';

class SummarizationService {
  SummarizationService({
    required PlatformBridgeService platformBridgeService,
    required AppLifecycleService appLifecycleService,
  }) : _platformBridgeService = platformBridgeService,
       _appLifecycleService = appLifecycleService;

  final PlatformBridgeService _platformBridgeService;
  final AppLifecycleService _appLifecycleService;

  Future<Map<String, dynamic>> summarize({
    required String requestId,
    required Map<String, dynamic> payload,
  }) async {
    if (!Platform.isAndroid) {
      throw PlatformException(
        code: NativeErrorCode.androidOnly,
        message: 'Summarization is Android-only.',
      );
    }

    if (!_appLifecycleService.isForeground) {
      throw PlatformException(
        code: NativeErrorCode.backgroundUseBlocked,
        message:
            'GenAI summarization is blocked while the app is backgrounded.',
      );
    }

    return _platformBridgeService.runSummarization(<String, dynamic>{
      'requestId': requestId,
      ...payload,
    });
  }
}
