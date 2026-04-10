const SHELL_CACHE = "inkcreate-shell-v7";
const OFFLINE_URL = "/offline.html";
const DB_NAME = "inkcreate-pwa";
const DB_VERSION = 3;
const DRAFT_STORE = "draftCaptures";
const UPLOAD_STORE = "pendingUploads";
const SYNC_STORE = "syncEvents";
const PREFERENCES_STORE = "appPreferences";
const NOTIFICATION_PREFERENCE_ID = "notificationPreferences";
const SYNC_NOTIFICATION_TAG = "inkcreate-sync-status";
const SHELL_ASSET_PREFIXES = ["/scripts/", "/inapp/", "/icons/"];
const SHELL_ASSET_PATHS = [OFFLINE_URL, "/manifest.json"];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(SHELL_CACHE).then((cache) => cache.addAll([
      OFFLINE_URL,
      "/manifest.json",
      "/icons/app-icon.svg",
      "/inapp/inapp_admin.css",
      "/inapp/inapp_admin.js",
      "/inapp/inapp_workspace.css",
      "/inapp/inapp_workspace.js",
      "/scripts/app.js",
      "/scripts/indexed-db.js",
      "/scripts/notification_preferences.js",
      "/scripts/vendor/stimulus.js",
      "/scripts/controllers/offline_status_controller.js",
      "/scripts/controllers/install_prompt_controller.js",
      "/scripts/controllers/camera_controller.js",
      "/scripts/controllers/queue_controller.js",
      "/scripts/controllers/search_filters_controller.js",
      "/scripts/controllers/notification_preferences_controller.js"
    ]))
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => Promise.all(
      cacheNames.filter((cacheName) => cacheName !== SHELL_CACHE).map((cacheName) => caches.delete(cacheName))
    )).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const requestUrl = new URL(event.request.url);

  if (event.request.method === "GET" && requestUrl.origin === self.location.origin && shellAssetRequest(requestUrl.pathname)) {
    event.respondWith(networkFirstShellAsset(event.request));
    return;
  }

  if (event.request.mode !== "navigate") {
    return;
  }

  event.respondWith(
    fetch(event.request).catch(() => caches.match(OFFLINE_URL))
  );
});

async function networkFirstShellAsset(request) {
  try {
    const response = await fetch(request);

    if (response.ok) {
      const cache = await caches.open(SHELL_CACHE);
      cache.put(request, response.clone());
    }

    return response;
  } catch (_error) {
    const cached = await caches.match(request);

    if (cached) {
      return cached;
    }

    const requestUrl = new URL(request.url);

    if (requestUrl.search) {
      const fallback = await caches.match(requestUrl.pathname);

      if (fallback) {
        return fallback;
      }
    }

    throw _error;
  }
}

function shellAssetRequest(pathname) {
  return SHELL_ASSET_PREFIXES.some((prefix) => pathname.startsWith(prefix)) || SHELL_ASSET_PATHS.includes(pathname);
}

self.addEventListener("sync", (event) => {
  if (event.tag === "inkcreate-sync") {
    event.waitUntil(replayUploadQueue());
  }
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(focusOrOpenClient(event.notification.data?.url || "/capture"));
});

async function replayUploadQueue() {
  const uploads = await allQueuedUploads();
  let syncedCount = 0;

  for (const upload of uploads) {
    try {
      const { draft, file, csrfToken } = upload;

      const uploadUrlResponse = await fetch("/api/v1/upload_urls", {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({
          upload: {
            filename: file.name,
            content_type: file.type,
            byte_size: file.size
          }
        })
      });

      if (!uploadUrlResponse.ok) {
        continue;
      }

      const uploadUrlPayload = await uploadUrlResponse.json();
      const uploadResponse = await fetch(uploadUrlPayload.signed_url, {
        method: "PUT",
        headers: uploadUrlPayload.headers,
        body: file
      });

      if (!uploadResponse.ok) {
        continue;
      }

      const createResponse = await fetch("/api/v1/captures", {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({
          capture: {
            project_id: draft.project_id,
            physical_page_id: draft.physical_page_id,
            page_type: draft.page_type,
            page_template_key: draft.page_type,
            title: draft.title,
            object_key: uploadUrlPayload.object_key,
            original_filename: file.name,
            save_destination: draft.save_destination,
            client_draft_id: draft.id,
            metadata: draft.metadata
          }
        })
      });

      if (createResponse.ok) {
        await deleteFromStore(UPLOAD_STORE, upload.id);
        await deleteFromStore(DRAFT_STORE, upload.id);
        syncedCount += 1;
      }
    } catch (_error) {
      // Leave the record in IndexedDB for the next retry.
    }
  }

  await notifyReplayResult(syncedCount, uploads.length);
}

function openDatabase() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onupgradeneeded = () => {
      [DRAFT_STORE, UPLOAD_STORE, SYNC_STORE, PREFERENCES_STORE].forEach((storeName) => {
        if (!request.result.objectStoreNames.contains(storeName)) {
          request.result.createObjectStore(storeName, { keyPath: "id" });
        }
      });
    };

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function allQueuedUploads() {
  const db = await openDatabase();

  return new Promise((resolve, reject) => {
    const tx = db.transaction(UPLOAD_STORE, "readonly");
    const store = tx.objectStore(UPLOAD_STORE);
    const request = store.getAll();

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function notificationPreference() {
  const preference = await getFromStore(PREFERENCES_STORE, NOTIFICATION_PREFERENCE_ID);
  return preference || { id: NOTIFICATION_PREFERENCE_ID, enabled: true };
}

async function notificationsEnabled() {
  if (!self.Notification || Notification.permission !== "granted") {
    return false;
  }

  const preference = await notificationPreference();
  return preference.enabled !== false;
}

async function notifyReplayResult(syncedCount, attemptedCount) {
  if (syncedCount <= 0 || attemptedCount <= 0 || !(await notificationsEnabled())) {
    return;
  }

  const remainingCount = (await allQueuedUploads()).length;
  const title = remainingCount > 0 ? "Inkcreate sync partially complete" : "Inkcreate sync complete";
  const body = remainingCount > 0
    ? `${syncedCount} queued ${pluralize("upload", syncedCount)} finished. ${remainingCount} ${pluralize("upload", remainingCount)} will retry again.`
    : `${syncedCount} queued ${pluralize("upload", syncedCount)} finished in the background.`;

  await self.registration.showNotification(title, {
    body,
    tag: SYNC_NOTIFICATION_TAG,
    renotify: true,
    icon: "/icons/app-icon.svg",
    badge: "/icons/app-icon.svg",
    data: { url: "/capture" }
  });
}

function pluralize(word, count) {
  return count === 1 ? word : `${word}s`;
}

async function focusOrOpenClient(pathname) {
  const targetUrl = new URL(pathname, self.location.origin).toString();
  const windowClients = await self.clients.matchAll({ type: "window", includeUncontrolled: true });

  for (const client of windowClients) {
    const clientUrl = new URL(client.url);

    if (clientUrl.origin !== self.location.origin) {
      continue;
    }

    if ("focus" in client) {
      await client.focus();
    }

    if ("navigate" in client) {
      await client.navigate(targetUrl);
    }

    return;
  }

  await self.clients.openWindow(targetUrl);
}

async function deleteQueuedUpload(id) {
  return deleteFromStore(UPLOAD_STORE, id);
}

async function deleteFromStore(storeName, id) {
  const db = await openDatabase();

  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, "readwrite");
    const store = tx.objectStore(storeName);
    const request = store.delete(id);

    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
  });
}

async function getFromStore(storeName, id) {
  const db = await openDatabase();

  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, "readonly");
    const store = tx.objectStore(storeName);
    const request = store.get(id);

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}
