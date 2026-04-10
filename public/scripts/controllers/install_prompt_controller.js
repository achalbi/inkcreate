import { Controller } from "/scripts/vendor/stimulus.js";
import {
  enableNotificationsForInstall,
  notificationPreferenceState
} from "/scripts/notification_preferences.js";

export default class extends Controller {
  static targets = ["notificationSetup", "notificationStatus", "notificationButton"];

  connect() {
    this.deferredPrompt = null;
    this.handleBeforeInstallPrompt = (event) => {
      event.preventDefault();
      this.deferredPrompt = event;
    };
    this.handleInstalled = () => {
      this.showNotificationSetup().catch(() => {
        // Keep install flow usable even if notification setup cannot be rendered.
      });
    };

    window.addEventListener("beforeinstallprompt", this.handleBeforeInstallPrompt);
    window.addEventListener("inkcreate:app-installed", this.handleInstalled);
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.handleBeforeInstallPrompt);
    window.removeEventListener("inkcreate:app-installed", this.handleInstalled);
  }

  async prompt() {
    if (this.deferredPrompt) {
      this.deferredPrompt.prompt();
      const installChoice = await this.deferredPrompt.userChoice;
      this.deferredPrompt = null;

      if (installChoice?.outcome === "accepted") {
        await enableNotificationsForInstall({
          requestPermission: false,
          showConfirmation: false
        });

        await this.showNotificationSetup();
      }

      return;
    }

    window.alert("Use your browser menu to install Inkcreate. On iPhone Safari, tap Share and then Add to Home Screen.");
  }

  async requestNotifications() {
    if (this.hasNotificationButtonTarget) {
      this.notificationButtonTarget.disabled = true;
      this.notificationButtonTarget.textContent = "Opening permission prompt...";
    }

    try {
      const state = await enableNotificationsForInstall({
        requestPermission: true,
        showConfirmation: true
      });
      this.renderNotificationSetup(state);
    } catch (_error) {
      const state = await notificationPreferenceState().catch(() => null);
      this.renderNotificationSetup(state, "Notifications could not be enabled right now. Please try again.");
    }
  }

  async showNotificationSetup() {
    if (!this.hasNotificationSetupTarget) {
      return;
    }

    this.notificationSetupTarget.hidden = false;
    this.renderNotificationSetup(await notificationPreferenceState());
  }

  renderNotificationSetup(state = null, feedback = "") {
    if (!this.hasNotificationSetupTarget) {
      return;
    }

    const nextState = state || {
      supported: false,
      enabled: false,
      permission: "unsupported"
    };

    if (this.hasNotificationStatusTarget) {
      this.notificationStatusTarget.textContent = feedback || this.notificationStatus(nextState);
    }

    if (this.hasNotificationButtonTarget) {
      const permissionGranted = nextState.permission === "granted";
      const permissionBlocked = nextState.permission === "denied";
      const unsupported = !nextState.supported;

      this.notificationButtonTarget.hidden = permissionGranted || permissionBlocked || unsupported;
      this.notificationButtonTarget.disabled = false;
      this.notificationButtonTarget.textContent = "Enable notifications";
    }
  }

  notificationStatus(state) {
    if (!state.supported) {
      return "This browser does not support app notifications for Inkcreate.";
    }

    if (state.permission === "granted") {
      return "Notifications are enabled for this device. Background sync updates can now appear after install.";
    }

    if (state.permission === "denied") {
      return "Notifications are blocked in browser settings. Re-enable them there first, then return to Settings if you want to turn them on later.";
    }

    return "Install accepted. Finish setup by allowing notifications for background upload and sync updates on this device.";
  }
}
