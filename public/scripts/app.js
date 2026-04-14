import { Application } from "/scripts/vendor/stimulus.js";
import OfflineStatusController from "/scripts/controllers/offline_status_controller.js";
import InstallPromptController from "/scripts/controllers/install_prompt_controller.js";
import CameraController from "/scripts/controllers/camera_controller.js";
import PhotoCaptureController from "/scripts/controllers/photo_capture_controller.js";
import QueueController from "/scripts/controllers/queue_controller.js";
import SearchFiltersController from "/scripts/controllers/search_filters_controller.js";
import LiveSearchController from "/scripts/controllers/live_search_controller.js";
import ListModalController from "/scripts/controllers/list_modal_controller.js";
import MoveDestinationController from "/scripts/controllers/move_destination_controller.js";
import NotificationPreferencesController from "/scripts/controllers/notification_preferences_controller.js";
import DriveOauthController from "/scripts/controllers/drive_oauth_controller.js";
import RichTextController from "/scripts/controllers/rich_text_controller.js";
import QuickCaptureController from "/scripts/controllers/quick_capture_controller.js";
import FooterActionMenuController from "/scripts/controllers/footer_action_menu_controller.js";
import VoiceRecorderController from "/scripts/controllers/voice_recorder_controller.js";
import VoiceNotePlayerController from "/scripts/controllers/voice_note_player_controller.js";
import TodoListController from "/scripts/controllers/todo_list_controller.js";
import ReminderFormController from "/scripts/controllers/reminder_form_controller.js";
import DevicePushController from "/scripts/controllers/device_push_controller.js";
import ReminderDismissConfirmController from "/scripts/controllers/reminder_dismiss_confirm_controller.js";
import TaskManagerController from "/scripts/controllers/task_manager_controller.js";
import DocumentCaptureController from "/scripts/controllers/document_capture_controller.js";
import SectionShortcutsController from "/scripts/controllers/section_shortcuts_controller.js";
import { enableNotificationsForInstall } from "/scripts/notification_preferences.js";

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
application.register("live-search", LiveSearchController);
application.register("list-modal", ListModalController);
application.register("move-destination", MoveDestinationController);
application.register("notification-preferences", NotificationPreferencesController);
application.register("drive-oauth", DriveOauthController);
application.register("rich-text", RichTextController);
application.register("quick-capture", QuickCaptureController);
application.register("footer-action-menu", FooterActionMenuController);
application.register("voice-recorder", VoiceRecorderController);
application.register("voice-note-player", VoiceNotePlayerController);
application.register("todo-list", TodoListController);
application.register("reminder-form", ReminderFormController);
application.register("device-push", DevicePushController);
application.register("reminder-dismiss-confirm", ReminderDismissConfirmController);
application.register("task-manager", TaskManagerController);
application.register("document-capture", DocumentCaptureController);
application.register("section-shortcuts", SectionShortcutsController);

document.addEventListener("DOMContentLoaded", () => scheduleTimedMessages());
document.addEventListener("turbo:load", () => scheduleTimedMessages());
window.addEventListener("appinstalled", () => {
  enableNotificationsForInstall({ requestPermission: false }).catch(() => {
    // Ignore install notification opt-in failures and keep the app usable.
  });
  window.dispatchEvent(new CustomEvent("inkcreate:app-installed"));
});

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/service-worker.js").then((registration) => {
      registration.update();
    }).catch(() => {
      // Ignore service worker registration failures and keep the app usable.
    });
  });
}
