import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'features/about/about_page.dart';
import 'features/settings/settings_page.dart';
import 'features/web_shell/web_shell_page.dart';
import 'features/web_shell/webview_controller_service.dart';

GoRouter buildAppRouter({
  required GlobalKey<NavigatorState> navigatorKey,
  required WebViewControllerService webviewControllerService,
}) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            WebShellPage(controllerService: webviewControllerService),
      ),
      GoRoute(
        path: '/settings',
        builder: (BuildContext context, GoRouterState state) =>
            const SettingsPage(),
      ),
      GoRoute(
        path: '/about',
        builder: (BuildContext context, GoRouterState state) =>
            const AboutPage(),
      ),
    ],
  );
}
