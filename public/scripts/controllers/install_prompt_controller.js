import { Controller } from "/scripts/vendor/stimulus.js";
import {
  enableNotificationsForInstall,
  notificationPreferenceState
} from "/scripts/notification_preferences.js";

const INSTALL_PROMPT_COLLAPSED_STORAGE_KEY = "inkcreate.installPrompt.collapsed";

export default class extends Controller {
  static targets = ["notificationSetup", "notificationStatus", "notificationButton", "promptButton", "panelBody", "collapseButton"];

  connect() {
    this.deferredPrompt = null;
    this.installState = null;
    this.handleBeforeInstallPrompt = (event) => {
      event.preventDefault();
      this.deferredPrompt = event;
    };
    this.handleInstalled = async () => {
      this.setPromptButtonHidden(true);
      this.installState = await notificationPreferenceState().catch(() => ({
        supported: true,
        installed: true,
        permission: "default"
      }));
      this.showNotificationSetup(this.installState).catch(() => {
        // Keep install flow usable even if notification setup cannot be rendered.
      });
      this.setCollapsed(true, { persist: true });
    };

    window.addEventListener("beforeinstallprompt", this.handleBeforeInstallPrompt);
    window.addEventListener("inkcreate:app-installed", this.handleInstalled);

    this.syncInstallState().catch(() => {
      // Ignore install state lookup failures and keep the app usable.
    });
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.handleBeforeInstallPrompt);
    window.removeEventListener("inkcreate:app-installed", this.handleInstalled);
  }

  toggleCollapse() {
    this.setCollapsed(!this.collapsed(), { persist: true });
  }

  async prompt() {
    if (this.deferredPrompt) {
      this.deferredPrompt.prompt();
      const installChoice = await this.deferredPrompt.userChoice;
      this.deferredPrompt = null;

      if (installChoice?.outcome === "accepted") {
        this.setPromptButtonHidden(true);
        await enableNotificationsForInstall({
          requestPermission: false,
          showConfirmation: false
        });

        await this.showNotificationSetup();
        this.setCollapsed(true, { persist: true });
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

  async showNotificationSetup(state = null) {
    if (!this.hasNotificationSetupTarget) {
      return;
    }

    this.notificationSetupTarget.hidden = false;
    this.renderNotificationSetup(state || await notificationPreferenceState());
  }

  async syncInstallState() {
    const state = await notificationPreferenceState();
    this.installState = state;
    this.setPromptButtonHidden(Boolean(state?.installed));
    const storedCollapsed = this.readCollapsedPreference();
    const collapsed = storedCollapsed === null ? Boolean(state?.installed) : storedCollapsed;

    if (state?.installed) {
      await this.showNotificationSetup(state);
    }

    this.setCollapsed(collapsed, {
      persist: storedCollapsed === null && collapsed
    });
  }

  setPromptButtonHidden(hidden) {
    if (this.hasPromptButtonTarget) {
      this.promptButtonTarget.hidden = hidden;
    }
  }

  setCollapsed(collapsed, { persist = false } = {}) {
    if (this.hasPanelBodyTarget) {
      this.panelBodyTarget.hidden = collapsed;
      this.panelBodyTarget.style.display = collapsed ? "none" : "";
      this.panelBodyTarget.setAttribute("aria-hidden", String(collapsed));
    }

    if (this.hasCollapseButtonTarget) {
      this.collapseButtonTarget.setAttribute("aria-expanded", String(!collapsed));
      this.collapseButtonTarget.setAttribute("title", collapsed ? "Expand section" : "Collapse section");
      this.collapseButtonTarget.setAttribute("aria-label", collapsed ? "Expand section" : "Collapse section");
    }

    this.element.dataset.installPromptCollapsed = collapsed ? "true" : "false";

    if (persist) {
      this.writeCollapsedPreference(collapsed);
    }
  }

  collapsed() {
    return this.hasPanelBodyTarget ? this.panelBodyTarget.hidden : this.element.dataset.installPromptCollapsed === "true";
  }

  readCollapsedPreference() {
    try {
      const value = window.localStorage?.getItem(INSTALL_PROMPT_COLLAPSED_STORAGE_KEY);
      if (value === "true") return true;
      if (value === "false") return false;
    } catch (_error) {
      return null;
    }

    return null;
  }

  writeCollapsedPreference(collapsed) {
    try {
      window.localStorage?.setItem(INSTALL_PROMPT_COLLAPSED_STORAGE_KEY, String(Boolean(collapsed)));
    } catch (_error) {
      // Ignore storage failures and keep the app usable.
    }
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
