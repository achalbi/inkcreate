import { Controller } from "/scripts/vendor/stimulus.js";
import {
  enableNotificationsForInstall,
  notificationPreferenceState
} from "/scripts/notification_preferences.js";

const INSTALL_PROMPT_COLLAPSED_STORAGE_KEY = "inkcreate.installPrompt.collapsed";
const INSTALL_PROMPT_DISMISSED_STORAGE_KEY = "inkcreate.installPrompt.dismissed";
const INSTALL_PROMPT_INSTALLED_STORAGE_KEY = "inkcreate.installPrompt.installed";

export default class extends Controller {
  static values = {
    forceShowPromptButton: Boolean
  };

  static targets = [
    "availabilityNote",
    "collapseButton",
    "manualInstructions",
    "notificationButton",
    "notificationSetup",
    "notificationStatus",
    "panelBody",
    "promptButton"
  ];

  connect() {
    this.deferredPrompt = window.__inkcreateDeferredInstallPrompt || null;
    this.installState = null;
    this.manualInstructionsVisible = false;
    this.promptAccepted = false;
    this.defaultPromptLabel = this.hasPromptButtonTarget ? this.promptButtonTarget.textContent.trim() : "Install Inkcreate";
    this.handleInstallAvailable = () => {
      this.deferredPrompt = window.__inkcreateDeferredInstallPrompt || null;
      this.syncInstallState().catch(() => {
        // Ignore install state lookup failures and keep the app usable.
      });
    };
    this.handleInstalled = async () => {
      this.promptAccepted = true;
      this.deferredPrompt = null;
      window.__inkcreateDeferredInstallPrompt = null;
      this.clearDismissedPreference();
      this.writeInstalledPreference(true);
      this.syncInstallState({ revealNotificationSetup: true }).catch(() => {
        // Keep install flow usable even if notification setup cannot be rendered.
      });
    };

    window.addEventListener("inkcreate:install-available", this.handleInstallAvailable);
    window.addEventListener("inkcreate:app-installed", this.handleInstalled);

    this.syncInstallState().catch(() => {
      // Ignore install state lookup failures and keep the app usable.
    });
  }

  disconnect() {
    window.removeEventListener("inkcreate:install-available", this.handleInstallAvailable);
    window.removeEventListener("inkcreate:app-installed", this.handleInstalled);
  }

  toggleCollapse() {
    this.setCollapsed(!this.collapsed(), { persist: true });
  }

  async prompt() {
    const availability = this.installAvailability(this.installState);

    if (availability.kind === "manual") {
      this.manualInstructionsVisible = true;
      this.setCollapsed(false, { persist: true });
      this.renderInstallState(availability);

      if (this.hasManualInstructionsTarget && this.manualInstructionsTarget.scrollIntoView) {
        this.manualInstructionsTarget.scrollIntoView({ block: "nearest", behavior: "smooth" });
      }

      return;
    }

    if (availability.kind === "prompt" && this.deferredPrompt) {
      this.deferredPrompt.prompt();
      const installChoice = await this.deferredPrompt.userChoice;
      this.deferredPrompt = null;
      window.__inkcreateDeferredInstallPrompt = null;

      if (installChoice?.outcome === "accepted") {
        this.promptAccepted = true;
        this.clearDismissedPreference();
        this.writeInstalledPreference(true);
        await enableNotificationsForInstall({
          requestPermission: false,
          showConfirmation: false
        });

        await this.syncInstallState({ revealNotificationSetup: true });
        return;
      }

      this.writeDismissedPreference(true);
      await this.syncInstallState();
      return;
    }

    this.renderInstallState(availability);
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

  hideNotificationSetup() {
    if (this.hasNotificationSetupTarget) {
      this.notificationSetupTarget.hidden = true;
    }
  }

  async syncInstallState({ revealNotificationSetup = false } = {}) {
    const state = await notificationPreferenceState();
    this.installState = state;

    if (state?.installed) {
      this.writeInstalledPreference(true);
    }

    const availability = this.installAvailability(state);

    if (availability.kind !== "manual") {
      this.manualInstructionsVisible = false;
    }

    if (availability.kind === "installed" && (revealNotificationSetup || state?.installed || this.promptAccepted)) {
      await this.showNotificationSetup(state);
    } else {
      this.hideNotificationSetup();
    }

    this.renderInstallState(availability);

    const storedCollapsed = this.readCollapsedPreference();
    this.setCollapsed(storedCollapsed === null ? false : storedCollapsed);
  }

  setPromptButtonHidden(hidden) {
    if (this.hasPromptButtonTarget) {
      const shouldHide = this.forceShowPromptButtonValue && this.element.dataset.installPromptState !== "installed"
        ? false
        : hidden;
      this.promptButtonTarget.hidden = shouldHide;
    }
  }

  setPromptButtonLabel(label) {
    if (this.hasPromptButtonTarget) {
      this.promptButtonTarget.textContent = label;
    }
  }

  renderInstallState(availability) {
    this.element.dataset.installPromptState = availability.kind;
    this.setPromptButtonLabel(availability.promptLabel);
    this.setPromptButtonHidden(!availability.showPrompt);
    this.renderAvailabilityNote(availability.note);

    if (this.hasManualInstructionsTarget) {
      this.manualInstructionsTarget.hidden = !(availability.kind === "manual" && this.manualInstructionsVisible);
    }
  }

  renderAvailabilityNote(note = "") {
    if (!this.hasAvailabilityNoteTarget) {
      return;
    }

    this.availabilityNoteTarget.textContent = note;
    this.availabilityNoteTarget.hidden = note.length === 0;
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

  installAvailability(state = null) {
    const installed = this.installedPreferenceActive(state);

    if (installed) {
      return {
        kind: "installed",
        note: "Inkcreate is already installed on this device. Open it from your home screen or app shelf when you want the app shell.",
        promptLabel: this.defaultPromptLabel,
        showPrompt: false
      };
    }

    if (this.readDismissedPreference()) {
      return {
        kind: "dismissed",
        note: "Install dismissed for now. Use the install guide when you want to add Inkcreate later.",
        promptLabel: this.defaultPromptLabel,
        showPrompt: false
      };
    }

    if (this.deferredPrompt) {
      return {
        kind: "prompt",
        note: "This browser can install Inkcreate right now.",
        promptLabel: this.defaultPromptLabel,
        showPrompt: true
      };
    }

    if (this.manualInstallEligible()) {
      return {
        kind: "manual",
        note: "Safari on iPhone or iPad can add Inkcreate from the Share menu.",
        promptLabel: "Show Add to Home Screen steps",
        showPrompt: true
      };
    }

    return {
      kind: "unavailable",
      note: "This browser cannot install Inkcreate directly. Use Safari on iPhone/iPad or Chrome on Android when you want the app shell.",
      promptLabel: this.defaultPromptLabel,
      showPrompt: false
    };
  }

  installedPreferenceActive(state = null) {
    if (Boolean(state?.installed) || this.promptAccepted) {
      return true;
    }

    if (!this.readInstalledPreference()) {
      return false;
    }

    if (this.staleInstalledPreference(state)) {
      this.writeInstalledPreference(false);
      return false;
    }

    return true;
  }

  staleInstalledPreference(state = null) {
    if (Boolean(state?.installed) || this.promptAccepted) {
      return false;
    }

    if (this.deferredPrompt) {
      return true;
    }

    return this.forceShowPromptButtonValue && this.manualInstallEligible();
  }

  readDismissedPreference() {
    try {
      return window.localStorage?.getItem(INSTALL_PROMPT_DISMISSED_STORAGE_KEY) === "true";
    } catch (_error) {
      return false;
    }
  }

  writeDismissedPreference(dismissed) {
    try {
      if (dismissed) {
        window.localStorage?.setItem(INSTALL_PROMPT_DISMISSED_STORAGE_KEY, "true");
      } else {
        window.localStorage?.removeItem(INSTALL_PROMPT_DISMISSED_STORAGE_KEY);
      }
    } catch (_error) {
      // Ignore storage failures and keep the app usable.
    }
  }

  clearDismissedPreference() {
    this.writeDismissedPreference(false);
  }

  readInstalledPreference() {
    try {
      return window.localStorage?.getItem(INSTALL_PROMPT_INSTALLED_STORAGE_KEY) === "true";
    } catch (_error) {
      return false;
    }
  }

  writeInstalledPreference(installed) {
    try {
      if (installed) {
        window.localStorage?.setItem(INSTALL_PROMPT_INSTALLED_STORAGE_KEY, "true");
      } else {
        window.localStorage?.removeItem(INSTALL_PROMPT_INSTALLED_STORAGE_KEY);
      }
    } catch (_error) {
      // Ignore storage failures and keep the app usable.
    }
  }

  manualInstallEligible() {
    if (typeof window === "undefined") {
      return false;
    }

    if (window.matchMedia?.("(display-mode: standalone)")?.matches || window.navigator.standalone === true) {
      return false;
    }

    const userAgent = window.navigator.userAgent || "";
    const platform = window.navigator.platform || "";
    const maxTouchPoints = window.navigator.maxTouchPoints || 0;
    const appleMobileDevice = /iPad|iPhone|iPod/.test(userAgent) || (platform === "MacIntel" && maxTouchPoints > 1);
    const safariWebKit = /AppleWebKit/i.test(userAgent);
    const excludedBrowsers = /CriOS|FxiOS|EdgiOS|OPiOS|DuckDuckGo/i.test(userAgent);

    return appleMobileDevice && safariWebKit && !excludedBrowsers;
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
