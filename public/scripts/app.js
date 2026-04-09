import { Application } from "/scripts/vendor/stimulus.js";
import OfflineStatusController from "/scripts/controllers/offline_status_controller.js";
import InstallPromptController from "/scripts/controllers/install_prompt_controller.js";
import CameraController from "/scripts/controllers/camera_controller.js";
import PhotoCaptureController from "/scripts/controllers/photo_capture_controller.js";
import QueueController from "/scripts/controllers/queue_controller.js";
import SearchFiltersController from "/scripts/controllers/search_filters_controller.js";
import ListModalController from "/scripts/controllers/list_modal_controller.js";
import DriveOauthController from "/scripts/controllers/drive_oauth_controller.js";
import RichTextController from "/scripts/controllers/rich_text_controller.js";
import QuickCaptureController from "/scripts/controllers/quick_capture_controller.js";

const AUTO_DISMISS_DELAY_MS = 5000;
const AUTO_DISMISS_EXIT_MS = 280;

const dismissTimedMessage = (element) => {
  if (!element || !element.isConnected || element.dataset.autoDismissState === "dismissing") {
    return;
  }

  element.dataset.autoDismissState = "dismissing";
  element.style.transition = "opacity 0.28s ease, transform 0.28s ease";
  element.style.opacity = "0";
  element.style.transform = "translateY(-8px) scale(0.98)";

  window.setTimeout(() => {
    const parent = element.parentElement;

    if (element.isConnected) {
      element.remove();
    }

    if (parent?.matches(".flash-stack") && parent.childElementCount === 0) {
      parent.remove();
    }
  }, AUTO_DISMISS_EXIT_MS);
};

const scheduleTimedMessages = (root = document) => {
  root.querySelectorAll("[data-auto-dismiss]").forEach((element) => {
    if (element.dataset.autoDismissBound === "true") {
      return;
    }

    element.dataset.autoDismissBound = "true";

    const delay = Number.parseInt(element.dataset.autoDismiss || "", 10);
    const timeout = Number.isFinite(delay) ? delay : AUTO_DISMISS_DELAY_MS;

    window.setTimeout(() => dismissTimedMessage(element), timeout);
  });
};

const application = Application.start();
application.register("offline-status", OfflineStatusController);
application.register("install-prompt", InstallPromptController);
application.register("camera", CameraController);
application.register("photo-capture", PhotoCaptureController);
application.register("queue", QueueController);
application.register("search-filters", SearchFiltersController);
application.register("list-modal", ListModalController);
application.register("drive-oauth", DriveOauthController);
application.register("rich-text", RichTextController);
application.register("quick-capture", QuickCaptureController);

document.addEventListener("DOMContentLoaded", () => scheduleTimedMessages());
document.addEventListener("turbo:load", () => scheduleTimedMessages());

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    const isLocalWorkspace = ["localhost", "127.0.0.1"].includes(window.location.hostname);

    if (isLocalWorkspace) {
      navigator.serviceWorker.getRegistrations().then((registrations) => {
        registrations.forEach((registration) => registration.unregister());
      }).catch(() => {
        // Ignore cleanup failures in local development.
      });

      if ("caches" in window) {
        caches.keys().then((cacheKeys) => {
          cacheKeys
            .filter((cacheKey) => cacheKey.startsWith("inkcreate-shell"))
            .forEach((cacheKey) => caches.delete(cacheKey));
        }).catch(() => {
          // Ignore cache cleanup failures in local development.
        });
      }

      return;
    }

    navigator.serviceWorker.register("/service-worker.js").then((registration) => {
      registration.update();
    }).catch(() => {
      // Ignore service worker registration failures and keep the app usable.
    });
  });
}
