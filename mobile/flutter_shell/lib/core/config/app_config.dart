import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig({
    required this.productionBaseUrl,
    required this.debugBaseUrl,
  });

  final String productionBaseUrl;
  final String debugBaseUrl;

  String get initialBaseUrl => kDebugMode ? debugBaseUrl : productionBaseUrl;

  static Future<AppConfig> load() async {
    const String productionBaseUrl = 'https://inkcreate.thoughtbasics.com';
    const String debugOverride = String.fromEnvironment(
      'INKCREATE_DEBUG_BASE_URL',
    );

    return AppConfig(
      productionBaseUrl: productionBaseUrl,
      debugBaseUrl: debugOverride.isNotEmpty
          ? debugOverride
          : await _inferDebugBaseUrl(),
    );
  }

  static Future<String> _inferDebugBaseUrl() async {
    if (!kDebugMode) {
      return 'https://inkcreate.thoughtbasics.com';
    }

    if (Platform.isAndroid) {
      try {
        final AndroidDeviceInfo androidInfo = await DeviceInfoPlugin()
            .androidInfo;
        return androidInfo.isPhysicalDevice
            ? 'http://127.0.0.1:3000'
            : 'http://10.0.2.2:3000';
      } catch (_) {
        return 'http://10.0.2.2:3000';
      }
    }

    return 'http://localhost:3000';
  }
}
