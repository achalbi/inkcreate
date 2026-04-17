import 'dart:convert';

import '../../core/models/native_bridge_models.dart';

String inkCreateNativeBootstrapScript() {
  return '''
    (function() {
      if (window.__inkCreateNativeBootstrapApplied) {
        return;
      }
      window.__inkCreateNativeBootstrapApplied = true;
      if (typeof window.InkCreateNative === 'undefined' && typeof InkCreateNative !== 'undefined') {
        window.InkCreateNative = InkCreateNative;
      }
    })();
  ''';
}

String dispatchCapabilitiesScript(NativeCapabilities capabilities) {
  final String payload = jsonEncode(capabilities.toJson());
  return '''
    window.dispatchEvent(new CustomEvent("inkcreate:nativeCapabilities", {
      detail: $payload
    }));
  ''';
}

String dispatchResultScript(NativeRouteResult result) {
  final String payload = jsonEncode(result.toJson());
  return '''
    window.dispatchEvent(new CustomEvent("inkcreate:nativeResult", {
      detail: $payload
    }));
  ''';
}

String dispatchProgressScript(NativeProgressEvent event) {
  final String payload = jsonEncode(event.toJson());
  return '''
    window.dispatchEvent(new CustomEvent("inkcreate:nativeProgress", {
      detail: $payload
    }));
  ''';
}
