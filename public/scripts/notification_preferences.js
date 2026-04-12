import { localStore } from "/scripts/indexed-db.js";

const PREFERENCE_ID = "notificationPreferences";
const NOTIFICATION_TAG = "inkcreate-device-notifications";
const SYNC_NOTIFICATION_TAG = "inkcreate-sync-status";
const NOTIFICATION_ICON = "/icons/notification-leaf.svg";
const NOTIFICATION_BADGE = "/icons/notification-badge-leaf.svg";
const DEFAULT_PREFERENCE = {
  id: PREFERENCE_ID,
  enabled: true,
  updatedAt: null,
  source: "default"
};

function notificationsSupported() {
  return typeof window !== "undefined" &&
    "Notification" in window &&
    "indexedDB" in window &&
    "serviceWorker" in navigator;
}

function standaloneMode() {
  return window.matchMedia?.("(display-mode: standalone)")?.matches || window.navigator.standalone === true;
}

function permissionState() {
  if (!("Notification" in window)) {
    return "unsupported";
  }

  return Notification.permission;
}

async function readPreference() {
  if (!notificationsSupported()) {
    return { ...DEFAULT_PREFERENCE };
  }

  try {
    return (await localStore.get(localStore.stores.preferences, PREFERENCE_ID)) || { ...DEFAULT_PREFERENCE };
  } catch (_error) {
    return { ...DEFAULT_PREFERENCE };
  }
}

async function writePreference(enabled, source) {
  const record = {
    id: PREFERENCE_ID,
    enabled,
    source,
    updatedAt: new Date().toISOString()
  };

  if (!notificationsSupported()) {
    return record;
  }

  try {
    await localStore.put(localStore.stores.preferences, record);
  } catch (_error) {
    // Ignore storage failures and keep the UI responsive.
  }

  return record;
}

async function serviceWorkerRegistration() {
  if (!notificationsSupported()) {
    return null;
  }

  try {
    return await navigator.serviceWorker.ready;
  } catch (_error) {
    return null;
  }
}

async function requestPermissionIfNeeded(requestPermission) {
  const currentPermission = permissionState();

  if (currentPermission !== "default" || !requestPermission || !("Notification" in window)) {
    return currentPermission;
  }

  try {
    return await Notification.requestPermission();
  } catch (_error) {
    return permissionState();
  }
}

export async function notificationPreferenceState() {
  const preference = await readPreference();
  const permission = notificationsSupported() ? permissionState() : "unsupported";
  const enabled = preference.enabled !== false;
  const available = permission === "granted";

  return {
    supported: notificationsSupported(),
    installed: standaloneMode(),
    enabled,
    available,
    blocked: permission === "denied",
    permission,
    preference
  };
}

export async function showNotificationConfirmation({
  title = "Inkcreate notifications enabled",
  body = "Background upload updates will appear on this device."
} = {}) {
  const registration = await serviceWorkerRegistration();
  if (!registration || permissionState() !== "granted") {
    return false;
  }

  await registration.showNotification(title, {
    body,
    icon: NOTIFICATION_ICON,
    badge: NOTIFICATION_BADGE,
    tag: NOTIFICATION_TAG,
    renotify: false,
    data: { url: "/capture" }
  });

  return true;
}

export async function closeNotificationConfirmation() {
  const registration = await serviceWorkerRegistration();
  if (!registration?.getNotifications) {
    return;
  }

  const notificationGroups = await Promise.all([
    registration.getNotifications({ tag: NOTIFICATION_TAG }),
    registration.getNotifications({ tag: SYNC_NOTIFICATION_TAG })
  ]);

  notificationGroups.flat().forEach((notification) => notification.close());
}

export async function enableNotifications({
  requestPermission = true,
  showConfirmation = false,
  source = "settings"
} = {}) {
  await writePreference(true, source);

  const permission = await requestPermissionIfNeeded(requestPermission);
  const state = await notificationPreferenceState();

  if (showConfirmation && permission === "granted") {
    await showNotificationConfirmation();
  }

  return state;
}

export async function disableNotifications({ source = "settings" } = {}) {
  await writePreference(false, source);
  await closeNotificationConfirmation();
  return notificationPreferenceState();
}

export async function enableNotificationsForInstall({
  requestPermission = false,
  showConfirmation = false
} = {}) {
  return enableNotifications({
    requestPermission,
    showConfirmation,
    source: "install"
  });
}
