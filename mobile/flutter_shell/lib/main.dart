import 'package:flutter/widgets.dart';

import 'app.dart';
import 'app_router.dart';
import 'core/config/app_config.dart';
import 'core/services/app_lifecycle_service.dart';
import 'core/services/native_route_executor.dart';
import 'core/services/platform_bridge_service.dart';
import 'features/native_genai/prompt/prompt_service.dart';
import 'features/native_genai/summarization/summarization_service.dart';
import 'features/native_ml/entity_extraction/entity_extraction_service.dart';
import 'features/native_ml/language_identification/language_identification_service.dart';
import 'features/native_ml/translation/translation_service.dart';
import 'features/web_shell/external_navigation_service.dart';
import 'features/web_shell/native_capabilities_service.dart';
import 'features/web_shell/webview_controller_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final AppConfig config = await AppConfig.load();
  final AppLifecycleService lifecycleService = AppLifecycleService();
  final PlatformBridgeService platformBridgeService = PlatformBridgeService();
  final NativeCapabilitiesService capabilitiesService =
      NativeCapabilitiesService(platformBridgeService: platformBridgeService);
  final LanguageIdentificationService languageIdentificationService =
      LanguageIdentificationService();
  final TranslationService translationService = TranslationService();
  final EntityExtractionService entityExtractionService =
      EntityExtractionService();
  final SummarizationService summarizationService = SummarizationService(
    platformBridgeService: platformBridgeService,
    appLifecycleService: lifecycleService,
  );
  final PromptService promptService = PromptService(
    platformBridgeService: platformBridgeService,
    appLifecycleService: lifecycleService,
  );

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final NativeRouteExecutor nativeRouteExecutor = NativeRouteExecutor(
    navigatorKey: navigatorKey,
    capabilitiesService: capabilitiesService,
    platformBridgeService: platformBridgeService,
    languageIdentificationService: languageIdentificationService,
    translationService: translationService,
    entityExtractionService: entityExtractionService,
    summarizationService: summarizationService,
    promptService: promptService,
  );

  final WebViewControllerService webviewControllerService =
      WebViewControllerService(
        config: config,
        capabilitiesService: capabilitiesService,
        nativeRouteExecutor: nativeRouteExecutor,
        platformBridgeService: platformBridgeService,
        externalNavigationService: ExternalNavigationService(),
      );

  runApp(
    InkCreateApp(
      router: buildAppRouter(
        navigatorKey: navigatorKey,
        webviewControllerService: webviewControllerService,
      ),
    ),
  );
}
