(() => {
  const CAPABILITIES_EVENT = "inkcreate:nativeCapabilities";
  const RESULT_EVENT = "inkcreate:nativeResult";
  const PROGRESS_EVENT = "inkcreate:nativeProgress";
  const REQUEST_TIMEOUT_MS = 45000;
  const DEFAULT_UNAVAILABLE_MESSAGE = "InkCreate native shell is unavailable on this device.";

  const pendingResults = new Map();
  const pendingCapabilityRequests = new Set();
  let lastCapabilities = null;

  const randomSuffix = () => Math.random().toString(36).slice(2, 10);
  const nextRequestId = (prefix = "REQ") => {
    if (window.crypto?.randomUUID) {
      return `${prefix}_${window.crypto.randomUUID()}`;
    }

    return `${prefix}_${Date.now()}_${randomSuffix()}`;
  };

  const normalizeError = (error, fallbackCode = "FEATURE_UNAVAILABLE") => ({
    code: error?.code || fallbackCode,
    message: error?.message || DEFAULT_UNAVAILABLE_MESSAGE
  });

  const buildUnavailableResult = (route, requestId, error) => ({
    requestId,
    route,
    status: "unavailable",
    data: {},
    error: normalizeError(error)
  });

  const nativeHost = () => window.InkCreateNative || null;

  const nativePostMessage = (message) => {
    const host = nativeHost();
    if (!host || typeof host.postMessage !== "function") {
      return false;
    }

    host.postMessage(JSON.stringify(message));
    return true;
  };

  const resolvePendingResult = (detail) => {
    const requestId = detail?.requestId;
    if (!requestId || !pendingResults.has(requestId)) {
      return;
    }

    const pending = pendingResults.get(requestId);
    pendingResults.delete(requestId);
    window.clearTimeout(pending.timeoutId);
    pending.resolve(detail);
  };

  const rejectPendingResult = (requestId, route, error) => {
    if (!requestId || !pendingResults.has(requestId)) {
      return;
    }

    const pending = pendingResults.get(requestId);
    pendingResults.delete(requestId);
    window.clearTimeout(pending.timeoutId);
    pending.resolve(buildUnavailableResult(route, requestId, error));
  };

  window.addEventListener(CAPABILITIES_EVENT, (event) => {
    lastCapabilities = event.detail || null;

    pendingCapabilityRequests.forEach((resolve) => resolve(lastCapabilities));
    pendingCapabilityRequests.clear();
  });

  window.addEventListener(RESULT_EVENT, (event) => {
    resolvePendingResult(event.detail || {});
  });

  const requestCapabilities = ({ force = false } = {}) => {
    if (!force && lastCapabilities) {
      return Promise.resolve(lastCapabilities);
    }

    const requestId = nextRequestId("CAPS");
    const posted = nativePostMessage({
      action: "get_capabilities",
      requestId
    });

    if (!posted) {
      return Promise.resolve(lastCapabilities);
    }

    return new Promise((resolve) => {
      let settled = false;

      const finish = (capabilities) => {
        if (settled) {
          return;
        }

        settled = true;
        window.clearTimeout(timeoutId);
        pendingCapabilityRequests.delete(finish);
        resolve(capabilities || null);
      };

      const timeoutId = window.setTimeout(() => finish(lastCapabilities), REQUEST_TIMEOUT_MS);
      pendingCapabilityRequests.add(finish);
    });
  };

  const openNativeRoute = (route, payload = {}) => {
    const requestId = nextRequestId("REQ");

    if (!route) {
      return Promise.resolve(buildUnavailableResult(route, requestId, {
        code: "FEATURE_UNAVAILABLE",
        message: "A native route is required."
      }));
    }

    const posted = nativePostMessage({
      action: "open_native_route",
      route,
      requestId,
      payload
    });

    if (!posted) {
      return Promise.resolve(buildUnavailableResult(route, requestId));
    }

    return new Promise((resolve) => {
      const timeoutId = window.setTimeout(() => {
        rejectPendingResult(requestId, route, {
          code: "FEATURE_UNAVAILABLE",
          message: "Native route timed out."
        });
      }, REQUEST_TIMEOUT_MS);

      pendingResults.set(requestId, { resolve, timeoutId });
    });
  };

  const openNativeRouteViaUrlScheme = (route, params = {}) => {
    const requestId = params.requestId || nextRequestId("REQ");
    const query = new URLSearchParams({ requestId });

    Object.entries(params).forEach(([key, value]) => {
      if (key === "requestId" || value == null) {
        return;
      }

      query.set(key, typeof value === "string" ? value : JSON.stringify(value));
    });

    window.location.href = `inkcreate://native/${encodeURIComponent(route)}?${query.toString()}`;
    return requestId;
  };

  const routeCapability = (route) => lastCapabilities?.routes?.[route] || null;

  const bridge = {
    eventNames: {
      capabilities: CAPABILITIES_EVENT,
      result: RESULT_EVENT,
      progress: PROGRESS_EVENT
    },
    getLastCapabilities: () => lastCapabilities,
    getRouteCapability: routeCapability,
    isNativeShellAvailable: () => Boolean(nativeHost()),
    isRouteSupported: (route) => routeCapability(route)?.supported === true,
    openNativeRoute,
    openNativeRouteViaUrlScheme,
    requestCapabilities
  };

  window.InkCreateNativeBridge = bridge;

  if (bridge.isNativeShellAvailable()) {
    requestCapabilities().catch(() => {
      // Keep the web app usable if capability discovery fails.
    });
  }
})();
