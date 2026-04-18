import { Application } from "/scripts/vendor/stimulus.js";
import OfflineStatusController from "/scripts/controllers/offline_status_controller.js";
import InstallPromptController from "/scripts/controllers/install_prompt_controller.js";
import InstallPopupController from "/scripts/controllers/install_popup_controller.js";
import CameraController from "/scripts/controllers/camera_controller.js";
import PhotoCaptureController from "/scripts/controllers/photo_capture_controller.js";
import QueueController from "/scripts/controllers/queue_controller.js";
import SearchFiltersController from "/scripts/controllers/search_filters_controller.js";
import LiveSearchController from "/scripts/controllers/live_search_controller.js";
import ListModalController from "/scripts/controllers/list_modal_controller.js";
import MoveDestinationController from "/scripts/controllers/move_destination_controller.js";
import LocationPickerController from "/scripts/controllers/location_picker_controller.js";
import ContactCardsController from "/scripts/controllers/contact_cards_controller.js";
import NotificationPreferencesController from "/scripts/controllers/notification_preferences_controller.js";
import DriveOauthController from "/scripts/controllers/drive_oauth_controller.js";
import RichTextController from "/scripts/controllers/rich_text_controller.js";
import QuickCaptureController from "/scripts/controllers/quick_capture_controller.js";
import FooterActionMenuController from "/scripts/controllers/footer_action_menu_controller.js";
import NotepadQuickActionsController from "/scripts/controllers/notepad_quick_actions_controller.js";
import VoiceRecorderController from "/scripts/controllers/voice_recorder_controller.js";
import VoiceNoteListController from "/scripts/controllers/voice_note_list_controller.js";
import VoiceNotePlayerController from "/scripts/controllers/voice_note_player_controller.js";
import TodoListController from "/scripts/controllers/todo_list_controller.js";
import ReminderFormController from "/scripts/controllers/reminder_form_controller.js";
import DevicePushController from "/scripts/controllers/device_push_controller.js";
import ReminderDismissConfirmController from "/scripts/controllers/reminder_dismiss_confirm_controller.js";
import ReminderSnoozeController from "/scripts/controllers/reminder_snooze_controller.js";
import TaskManagerController from "/scripts/controllers/task_manager_controller.js";
import TaskDockController from "/scripts/controllers/task_dock_controller.js";
import DocumentCaptureController from "/scripts/controllers/document_capture_controller.js";
import ScannedDocumentOcrModalController from "/scripts/controllers/scanned_document_ocr_modal_controller.js";
import SectionShortcutsController from "/scripts/controllers/section_shortcuts_controller.js";
import StickyDockController from "/scripts/controllers/sticky_dock_controller.js";
import OnboardingWizardController from "/scripts/controllers/onboarding_wizard_controller.js";
import IdleShortcutsController from "/scripts/controllers/idle_shortcuts_controller.js";
import LauncherContinueScopeController from "/scripts/controllers/launcher_continue_scope_controller.js";
import LauncherLocationCaptureController from "/scripts/controllers/launcher_location_capture_controller.js";
import { enableNotificationsForInstall } from "/scripts/notification_preferences.js";

const AUTO_DISMISS_DELAY_MS = 5000;
const AUTO_DISMISS_EXIT_MS = 280;

window.__inkcreateDeferredInstallPrompt = window.__inkcreateDeferredInstallPrompt || null;

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
application.register("install-popup", InstallPopupController);
application.register("camera", CameraController);
application.register("photo-capture", PhotoCaptureController);
application.register("queue", QueueController);
application.register("search-filters", SearchFiltersController);
application.register("live-search", LiveSearchController);
application.register("list-modal", ListModalController);
application.register("move-destination", MoveDestinationController);
application.register("location-picker", LocationPickerController);
application.register("contact-cards", ContactCardsController);
application.register("notification-preferences", NotificationPreferencesController);
application.register("drive-oauth", DriveOauthController);
application.register("rich-text", RichTextController);
application.register("quick-capture", QuickCaptureController);
application.register("footer-action-menu", FooterActionMenuController);
application.register("notepad-quick-actions", NotepadQuickActionsController);
application.register("voice-recorder", VoiceRecorderController);
application.register("voice-note-list", VoiceNoteListController);
application.register("voice-note-player", VoiceNotePlayerController);
application.register("todo-list", TodoListController);
application.register("reminder-form", ReminderFormController);
application.register("device-push", DevicePushController);
application.register("reminder-dismiss-confirm", ReminderDismissConfirmController);
application.register("reminder-snooze", ReminderSnoozeController);
application.register("task-manager", TaskManagerController);
application.register("task-dock", TaskDockController);
application.register("document-capture", DocumentCaptureController);
application.register("scanned-document-ocr-modal", ScannedDocumentOcrModalController);
application.register("section-shortcuts", SectionShortcutsController);
application.register("sticky-dock", StickyDockController);
application.register("onboarding-wizard", OnboardingWizardController);
application.register("idle-shortcuts", IdleShortcutsController);
application.register("launcher-continue-scope", LauncherContinueScopeController);
application.register("launcher-location-capture", LauncherLocationCaptureController);
document.addEventListener("DOMContentLoaded", () => scheduleTimedMessages());
document.addEventListener("turbo:load", () => scheduleTimedMessages());
window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault();
  window.__inkcreateDeferredInstallPrompt = event;
  window.dispatchEvent(new CustomEvent("inkcreate:install-available"));
});
window.addEventListener("appinstalled", () => {
  window.__inkcreateDeferredInstallPrompt = null;
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
