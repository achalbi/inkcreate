import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/models/native_bridge_models.dart';
import '../../core/services/platform_bridge_service.dart';

class NativeCapabilitiesService extends ChangeNotifier {
  NativeCapabilitiesService({
    required PlatformBridgeService platformBridgeService,
  }) : _platformBridgeService = platformBridgeService {
    _current = NativeCapabilities(
      platform: _platformName(),
      routes: _defaultRoutes(),
    );
  }

  final PlatformBridgeService _platformBridgeService;

  late NativeCapabilities _current;

  NativeCapabilities get current => _current;

  Future<NativeCapabilities> refresh({bool force = false}) async {
    final Map<String, NativeRouteCapability> routes = _defaultRoutes();

    if (Platform.isAndroid) {
      try {
        final Map<String, dynamic> androidCapabilities =
            await _platformBridgeService.fetchGenAiCapabilities();
        androidCapabilities.forEach((String route, dynamic value) {
          final Map<String, dynamic> capability = Map<String, dynamic>.from(
            value as Map? ?? const <String, dynamic>{},
          );
          routes[route] = NativeRouteCapability(
            supported: capability['supported'] == true,
            reason: capability['reason']?.toString(),
          );
        });
      } catch (_) {
        for (final String route in <String>[
          'genai:speech-recognition',
          'genai:summarization',
          'genai:prompt',
        ]) {
          routes[route] = const NativeRouteCapability(
            supported: false,
            reason: NativeErrorCode.integrationNotFinalized,
          );
        }
      }
    }

    _current = NativeCapabilities(platform: _platformName(), routes: routes);
    notifyListeners();
    return _current;
  }

  NativeRouteCapability capabilityFor(String route) {
    return _current.routes[route] ??
        const NativeRouteCapability(
          supported: false,
          reason: NativeErrorCode.featureUnavailable,
        );
  }

  static String _platformName() {
    if (Platform.isAndroid) {
      return 'android';
    }

    return 'ios';
  }

  static Map<String, NativeRouteCapability> _defaultRoutes() {
    return <String, NativeRouteCapability>{
      'mlkit:text-recognition-v2': const NativeRouteCapability(supported: true),
      'mlkit:barcode-scanning': const NativeRouteCapability(supported: true),
      'mlkit:language-identification': const NativeRouteCapability(
        supported: true,
      ),
      'mlkit:translation': const NativeRouteCapability(supported: true),
      'mlkit:entity-extraction': const NativeRouteCapability(supported: true),
      'mlkit:document-scanner': const NativeRouteCapability(supported: true),
      'genai:speech-recognition': NativeRouteCapability(
        supported: false,
        reason: Platform.isAndroid
            ? NativeErrorCode.featureUnavailable
            : NativeErrorCode.androidOnly,
      ),
      'genai:summarization': NativeRouteCapability(
        supported: false,
        reason: Platform.isAndroid
            ? NativeErrorCode.featureUnavailable
            : NativeErrorCode.androidOnly,
      ),
      'genai:prompt': NativeRouteCapability(
        supported: false,
        reason: Platform.isAndroid
            ? NativeErrorCode.featureUnavailable
            : NativeErrorCode.androidOnly,
      ),
    };
  }
}
