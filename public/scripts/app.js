import { Application } from "/scripts/vendor/stimulus.js";
import OfflineStatusController from "/scripts/controllers/offline_status_controller.js";
import InstallPromptController from "/scripts/controllers/install_prompt_controller.js";
import CameraController from "/scripts/controllers/camera_controller.js";
import PhotoCaptureController from "/scripts/controllers/photo_capture_controller.js";
import QueueController from "/scripts/controllers/queue_controller.js";
import SearchFiltersController from "/scripts/controllers/search_filters_controller.js";

const application = Application.start();
application.register("offline-status", OfflineStatusController);
application.register("install-prompt", InstallPromptController);
application.register("camera", CameraController);
application.register("photo-capture", PhotoCaptureController);
application.register("queue", QueueController);
application.register("search-filters", SearchFiltersController);

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/service-worker.js").then((registration) => {
      registration.update();
    }).catch(() => {
      // Ignore service worker registration failures and keep the app usable.
    });
  });
}
