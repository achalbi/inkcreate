import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

import '../../../core/models/native_bridge_models.dart';
import '../../../core/services/platform_bridge_service.dart';

class SpeechRecognitionPage extends StatefulWidget {
  const SpeechRecognitionPage({
    super.key,
    required this.requestId,
    required this.route,
    required this.payload,
    required this.platformBridgeService,
  });

  final String requestId;
  final String route;
  final Map<String, dynamic> payload;
  final PlatformBridgeService platformBridgeService;

  @override
  State<SpeechRecognitionPage> createState() => _SpeechRecognitionPageState();
}

class _SpeechRecognitionPageState extends State<SpeechRecognitionPage> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_started) {
      return;
    }

    _started = true;
    final PermissionStatus microphoneStatus = await Permission.microphone
        .request();
    if (!mounted) {
      return;
    }

    if (!microphoneStatus.isGranted) {
      Navigator.of(context).pop(
        NativeRouteResult.unavailable(
          requestId: widget.requestId,
          route: widget.route,
          code: NativeErrorCode.microphonePermissionDenied,
          message: 'Microphone permission is required for speech recognition.',
        ),
      );
      return;
    }

    try {
      final Map<String, dynamic> response = await widget.platformBridgeService
          .startSpeechRecognition(<String, dynamic>{
            'requestId': widget.requestId,
            ...widget.payload,
          });

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(
        NativeRouteResult.success(
          requestId: widget.requestId,
          route: widget.route,
          data: response,
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
