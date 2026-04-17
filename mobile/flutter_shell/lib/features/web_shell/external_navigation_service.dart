import 'package:url_launcher/url_launcher.dart';

class ExternalNavigationService {
  Future<bool> openIfExternal({
    required Uri requestUri,
    required Uri appUri,
  }) async {
    final bool isHttp =
        requestUri.scheme == 'http' || requestUri.scheme == 'https';
    final bool sameOrigin = requestUri.host == appUri.host;

    if (isHttp && sameOrigin) {
      return false;
    }

    if (requestUri.scheme == 'inkcreate') {
      return false;
    }

    await launchUrl(requestUri, mode: LaunchMode.externalApplication);
    return true;
  }
}
