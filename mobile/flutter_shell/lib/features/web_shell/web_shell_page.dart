import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'webview_controller_service.dart';

class WebShellPage extends StatefulWidget {
  const WebShellPage({super.key, required this.controllerService});

  final WebViewControllerService controllerService;

  @override
  State<WebShellPage> createState() => _WebShellPageState();
}

class _WebShellPageState extends State<WebShellPage> {
  WebViewController? _controller;
  WebShellViewState _viewState = WebShellViewState.loading;
  late final Stream<List<ConnectivityResult>> _connectivityStream;

  @override
  void initState() {
    super.initState();
    _connectivityStream = Connectivity().onConnectivityChanged;
    _load();
  }

  Future<void> _load() async {
    final WebViewController controller = await widget.controllerService.build(
      onStateChanged: (WebShellViewState state) {
        if (!mounted) {
          return;
        }

        setState(() => _viewState = state);
      },
    );

    if (!mounted) {
      return;
    }

    setState(() => _controller = controller);
  }

  Future<bool> _onWillPop() async {
    final bool handled = await widget.controllerService.handleBack();
    return !handled;
  }

  void _exitShell() {
    unawaited(SystemNavigator.pop());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          return;
        }

        final bool shouldExit = await _onWillPop();
        if (shouldExit && context.mounted) {
          _exitShell();
        }
      },
      child: Scaffold(
        body: Stack(
          children: <Widget>[
            if (_controller != null)
              Positioned.fill(child: WebViewWidget(controller: _controller!)),
            if (_viewState != WebShellViewState.ready)
              Positioned.fill(child: _overlay(context)),
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(
                child: Material(
                  color: Colors.white.withValues(alpha: 0.96),
                  elevation: 6,
                  shape: const CircleBorder(),
                  child: PopupMenuButton<String>(
                    tooltip: 'Shell menu',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (String value) {
                      if (value == 'settings') {
                        context.push('/settings');
                        return;
                      }

                      if (value == 'about') {
                        context.push('/about');
                        return;
                      }

                      widget.controllerService.reload();
                    },
                    itemBuilder: (BuildContext context) =>
                        const <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                            value: 'settings',
                            child: Text('Settings'),
                          ),
                          PopupMenuItem<String>(
                            value: 'about',
                            child: Text('About'),
                          ),
                          PopupMenuItem<String>(
                            value: 'reload',
                            child: Text('Reload'),
                          ),
                        ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overlay(BuildContext context) {
    switch (_viewState) {
      case WebShellViewState.loading:
        return _stateCard(
          context,
          title: 'Loading InkCreate',
          description:
              'Starting the web shell and syncing native capabilities.',
          child: const CircularProgressIndicator(),
        );
      case WebShellViewState.offline:
        return StreamBuilder<List<ConnectivityResult>>(
          stream: _connectivityStream,
          builder:
              (
                BuildContext context,
                AsyncSnapshot<List<ConnectivityResult>> snapshot,
              ) {
                return _stateCard(
                  context,
                  title: 'Offline',
                  description:
                      'The web app could not be reached. Retry once connectivity is back.',
                  child: ElevatedButton(
                    onPressed: () => widget.controllerService.reload(),
                    child: const Text('Retry'),
                  ),
                );
              },
        );
      case WebShellViewState.fatal:
        return _stateCard(
          context,
          title: 'Something went wrong',
          description:
              'The WebView could not load InkCreate. You can retry or return later.',
          child: ElevatedButton(
            onPressed: () => widget.controllerService.reload(),
            child: const Text('Retry'),
          ),
        );
      case WebShellViewState.ready:
        return const SizedBox.shrink();
    }
  }

  Widget _stateCard(
    BuildContext context, {
    required String title,
    required String description,
    required Widget child,
  }) {
    return ColoredBox(
      color: const Color(0xFFF6F1E7),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    blurRadius: 24,
                    offset: Offset(0, 12),
                    color: Color(0x22000000),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(description, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
