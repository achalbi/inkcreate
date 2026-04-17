import 'dart:convert';

typedef NativeProgressCallback =
    Future<void> Function(NativeProgressEvent event);

abstract final class NativeErrorCode {
  static const androidOnly = 'ANDROID_ONLY';
  static const featureUnavailable = 'FEATURE_UNAVAILABLE';
  static const deviceNotSupported = 'DEVICE_NOT_SUPPORTED';
  static const aiCoreUnavailable = 'AICORE_UNAVAILABLE';
  static const modelDownloadRequired = 'MODEL_DOWNLOAD_REQUIRED';
  static const modelDownloading = 'MODEL_DOWNLOADING';
  static const backgroundUseBlocked = 'BACKGROUND_USE_BLOCKED';
  static const osVersionTooLow = 'OS_VERSION_TOO_LOW';
  static const bootloaderUnlocked = 'BOOTLOADER_UNLOCKED';
  static const integrationNotFinalized = 'INTEGRATION_NOT_FINALIZED';
  static const cameraPermissionDenied = 'CAMERA_PERMISSION_DENIED';
  static const microphonePermissionDenied = 'MICROPHONE_PERMISSION_DENIED';
}

class NativeRouteCapability {
  const NativeRouteCapability({required this.supported, this.reason});

  final bool supported;
  final String? reason;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'supported': supported,
    'reason': reason,
  };
}

class NativeCapabilities {
  const NativeCapabilities({required this.platform, required this.routes});

  final String platform;
  final Map<String, NativeRouteCapability> routes;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'platform': platform,
    'routes': routes.map(
      (String key, NativeRouteCapability value) =>
          MapEntry<String, dynamic>(key, value.toJson()),
    ),
  };
}

class NativeRouteRequest {
  const NativeRouteRequest({
    required this.action,
    required this.requestId,
    this.route,
    this.payload = const <String, dynamic>{},
  });

  final String action;
  final String requestId;
  final String? route;
  final Map<String, dynamic> payload;

  static NativeRouteRequest? tryParse(String rawMessage) {
    try {
      final dynamic decoded = jsonDecode(rawMessage);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      return NativeRouteRequest(
        action: decoded['action']?.toString() ?? '',
        requestId: decoded['requestId']?.toString() ?? '',
        route: decoded['route']?.toString(),
        payload: decoded['payload'] is Map<String, dynamic>
            ? decoded['payload'] as Map<String, dynamic>
            : const <String, dynamic>{},
      );
    } catch (_) {
      return null;
    }
  }
}

class NativeRouteError {
  const NativeRouteError({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'code': code,
    'message': message,
  };
}

class NativeRouteResult {
  const NativeRouteResult({
    required this.requestId,
    required this.route,
    required this.status,
    this.data = const <String, dynamic>{},
    this.error,
  });

  final String requestId;
  final String route;
  final String status;
  final Map<String, dynamic> data;
  final NativeRouteError? error;

  factory NativeRouteResult.success({
    required String requestId,
    required String route,
    Map<String, dynamic> data = const <String, dynamic>{},
  }) {
    return NativeRouteResult(
      requestId: requestId,
      route: route,
      status: 'success',
      data: data,
    );
  }

  factory NativeRouteResult.error({
    required String requestId,
    required String route,
    required String code,
    required String message,
    Map<String, dynamic> data = const <String, dynamic>{},
  }) {
    return NativeRouteResult(
      requestId: requestId,
      route: route,
      status: 'error',
      data: data,
      error: NativeRouteError(code: code, message: message),
    );
  }

  factory NativeRouteResult.unavailable({
    required String requestId,
    required String route,
    required String code,
    required String message,
  }) {
    return NativeRouteResult(
      requestId: requestId,
      route: route,
      status: 'unavailable',
      error: NativeRouteError(code: code, message: message),
    );
  }

  factory NativeRouteResult.cancelled({
    required String requestId,
    required String route,
  }) {
    return NativeRouteResult(
      requestId: requestId,
      route: route,
      status: 'cancelled',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'requestId': requestId,
    'route': route,
    'status': status,
    'data': data,
    'error': error?.toJson(),
  };
}

class NativeProgressEvent {
  const NativeProgressEvent({
    required this.requestId,
    required this.route,
    required this.status,
    this.progress,
    this.partialData = const <String, dynamic>{},
  });

  final String requestId;
  final String route;
  final String status;
  final double? progress;
  final Map<String, dynamic> partialData;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'requestId': requestId,
    'route': route,
    'status': status,
    'progress': progress,
    'partialData': partialData,
  };
}
