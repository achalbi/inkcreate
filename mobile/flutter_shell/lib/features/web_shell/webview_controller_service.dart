import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/models/native_bridge_models.dart';
import '../../core/services/native_route_executor.dart';
import '../../core/services/platform_bridge_service.dart';
import 'external_navigation_service.dart';
import 'js_bridge.dart';
import 'native_capabilities_service.dart';

enum WebShellViewState { loading, ready, offline, fatal }

class WebViewControllerService {
  WebViewControllerService({
    required AppConfig config,
    required NativeCapabilitiesService capabilitiesService,
    required NativeRouteExecutor nativeRouteExecutor,
    required PlatformBridgeService platformBridgeService,
    required ExternalNavigationService externalNavigationService,
  }) : _config = config,
       _capabilitiesService = capabilitiesService,
       _nativeRouteExecutor = nativeRouteExecutor,
       _platformBridgeService = platformBridgeService,
       _externalNavigationService = externalNavigationService;

  final AppConfig _config;
  final NativeCapabilitiesService _capabilitiesService;
  final NativeRouteExecutor _nativeRouteExecutor;
  final PlatformBridgeService _platformBridgeService;
  final ExternalNavigationService _externalNavigationService;

  WebViewController? _controller;
  StreamSubscription<NativeProgressEvent>? _progressSubscription;

  Uri get initialUri => Uri.parse(_config.initialBaseUrl);

  Future<WebViewController> build({
    required ValueChanged<WebShellViewState> onStateChanged,
  }) async {
    if (_controller != null) {
      return _controller!;
    }

    _progressSubscription ??= _platformBridgeService.progressEvents().listen((
      NativeProgressEvent event,
    ) {
      _dispatchProgress(event);
    });

    final WebViewController controller = WebViewController();
    _controller = controller;

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'InkCreateNative',
        onMessageReceived: (JavaScriptMessage message) async {
          final NativeRouteRequest? request = NativeRouteRequest.tryParse(
            message.message,
          );
          if (request == null ||
              request.action.isEmpty ||
              request.requestId.isEmpty) {
            return;
          }

          if (request.action == 'get_capabilities') {
            final NativeCapabilities capabilities = await _capabilitiesService
                .refresh(force: true);
            await _dispatchCapabilities(capabilities);
            return;
          }

          if (request.action == 'open_native_route' && request.route != null) {
            final NativeRouteResult result = await _nativeRouteExecutor.execute(
              request,
              onProgress: _dispatchProgress,
            );
            await _dispatchResult(result);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) async {
            final Uri uri = Uri.parse(request.url);
            if (uri.scheme == 'inkcreate') {
              await _handleInkCreateScheme(uri);
              return NavigationDecision.prevent;
            }

            final bool openedExternally = await _externalNavigationService
                .openIfExternal(requestUri: uri, appUri: initialUri);
            return openedExternally
                ? NavigationDecision.prevent
                : NavigationDecision.navigate;
          },
          onPageStarted: (_) => onStateChanged(WebShellViewState.loading),
          onPageFinished: (_) async {
            await controller.runJavaScript(inkCreateNativeBootstrapScript());
            await _dispatchCapabilities(await _capabilitiesService.refresh());
            onStateChanged(WebShellViewState.ready);
          },
          onWebResourceError: (WebResourceError error) {
            final bool isNetworkError =
                error.errorType == WebResourceErrorType.connect ||
                error.errorType == WebResourceErrorType.hostLookup ||
                error.errorType == WebResourceErrorType.timeout;
            onStateChanged(
              isNetworkError
                  ? WebShellViewState.offline
                  : WebShellViewState.fatal,
            );
          },
        ),
      )
      ..loadRequest(initialUri);

    return controller;
  }

  Future<void> reload() async {
    await _controller?.reload();
  }

  Future<bool> handleBack() async {
    if (_controller == null) {
      return false;
    }

    if (await _controller!.canGoBack()) {
      await _controller!.goBack();
      return true;
    }

    return false;
  }

  Future<void> _dispatchCapabilities(NativeCapabilities capabilities) async {
    await _controller?.runJavaScript(dispatchCapabilitiesScript(capabilities));
  }

  Future<void> _dispatchResult(NativeRouteResult result) async {
    await _controller?.runJavaScript(dispatchResultScript(result));
  }

  Future<void> _dispatchProgress(NativeProgressEvent event) async {
    await _controller?.runJavaScript(dispatchProgressScript(event));
  }

  Future<void> _handleInkCreateScheme(Uri uri) async {
    if (uri.host != 'native') {
      return;
    }

    final String route = Uri.decodeComponent(
      uri.path.replaceFirst(RegExp(r'^/+'), ''),
    );
    if (route.isEmpty) {
      return;
    }

    Map<String, dynamic> payload = const <String, dynamic>{};
    final String? payloadParam = uri.queryParameters['payload'];
    if (payloadParam != null && payloadParam.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(payloadParam);
        if (decoded is Map<String, dynamic>) {
          payload = decoded;
        }
      } catch (_) {
        payload = const <String, dynamic>{};
      }
    }

    final NativeRouteRequest request = NativeRouteRequest(
      action: 'open_native_route',
      requestId:
          uri.queryParameters['requestId'] ??
          'URL_${DateTime.now().millisecondsSinceEpoch}',
      route: route,
      payload: payload,
    );

    final NativeRouteResult result = await _nativeRouteExecutor.execute(
      request,
    );
    await _dispatchResult(result);
  }
}
