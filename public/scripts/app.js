import { Application } from "/scripts/vendor/stimulus.js";
import OfflineStatusController from "/scripts/controllers/offline_status_controller.js";
import InstallPromptController from "/scripts/controllers/install_prompt_controller.js";
import CameraController from "/scripts/controllers/camera_controller.js";
import PhotoCaptureController from "/scripts/controllers/photo_capture_controller.js";
import QueueController from "/scripts/controllers/queue_controller.js";
import SearchFiltersController from "/scripts/controllers/search_filters_controller.js";
import ListModalController from "/scripts/controllers/list_modal_controller.js";
import DriveOauthController from "/scripts/controllers/drive_oauth_controller.js";

const application = Application.start();
application.register("offline-status", OfflineStatusController);
application.register("install-prompt", InstallPromptController);
application.register("camera", CameraController);
application.register("photo-capture", PhotoCaptureController);
application.register("queue", QueueController);
application.register("search-filters", SearchFiltersController);
application.register("list-modal", ListModalController);
application.register("drive-oauth", DriveOauthController);

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
