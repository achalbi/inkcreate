import { Controller } from "/scripts/vendor/stimulus.js";
import {
  disableNotifications,
  enableNotifications,
  notificationPreferenceState
} from "/scripts/notification_preferences.js";

export default class extends Controller {
  static targets = [
    "permissionStatus",
    "deviceStatus",
    "helpText",
    "feedback",
    "enableButton",
    "disableButton"
  ];

  async connect() {
    this.isBusy = false;
    await this.renderState();
  }

  async enable() {
    await this.runAction(async () => {
      const state = await enableNotifications({
        requestPermission: true,
        showConfirmation: true,
        source: "settings"
      });

      return {
        state,
        feedback: this.enableFeedback(state)
      };
    });
  }

  async disable() {
    await this.runAction(async () => {
      const state = await disableNotifications({ source: "settings" });

      return {
        state,
        feedback: "Notifications are turned off for this device. You can re-enable them here anytime."
      };
    });
  }

  async runAction(action) {
    this.setBusy(true);
    await this.renderState();

    let nextState = null;
    let feedback = "";

    try {
      const result = await action();
      nextState = result?.state || null;
      feedback = result?.feedback || "";
    } catch (_error) {
      feedback = "Notifications could not be updated on this device right now.";
    } finally {
      this.setBusy(false);
    }

    await this.renderState(nextState, feedback);
  }

  async renderState(nextState = null, feedback = "") {
    const state = nextState || await notificationPreferenceState();

    if (this.hasPermissionStatusTarget) {
      this.permissionStatusTarget.textContent = this.permissionLabel(state);
    }

    if (this.hasDeviceStatusTarget) {
      this.deviceStatusTarget.textContent = this.deviceLabel(state);
    }

    if (this.hasHelpTextTarget) {
      this.helpTextTarget.textContent = this.helpText(state);
    }

    if (this.hasFeedbackTarget) {
      this.feedbackTarget.textContent = feedback;
      this.feedbackTarget.hidden = feedback.length === 0;
    }

    if (this.hasEnableButtonTarget) {
      const blockedByBrowser = state.permission === "denied";
      const alreadyEnabled = state.enabled && state.permission === "granted";
      this.enableButtonTarget.disabled = this.isBusy || !state.supported || blockedByBrowser || alreadyEnabled;
      this.enableButtonTarget.textContent = alreadyEnabled ? "Notifications enabled" : "Enable notifications";
    }

    if (this.hasDisableButtonTarget) {
      this.disableButtonTarget.disabled = this.isBusy || !state.supported || !state.enabled;
    }
  }

  setBusy(isBusy) {
    this.isBusy = isBusy;
  }

  permissionLabel(state) {
    switch (state.permission) {
      case "granted":
        return "Allowed";
      case "denied":
        return "Blocked by browser";
      case "default":
        return "Not requested yet";
      default:
        return "Unsupported on this device";
    }
  }

  deviceLabel(state) {
    if (!state.supported) {
      return "Unavailable";
    }

    if (!state.enabled) {
      return "Disabled for this device";
    }

    if (state.available) {
      return "Enabled";
    }

    if (state.permission === "denied") {
      return "Waiting for browser re-enable";
    }

    return "Ready once permission is granted";
  }

  helpText(state) {
    if (!state.supported) {
      return "This browser does not support service worker notifications for Inkcreate.";
    }

    if (!state.enabled) {
      return "Turn notifications back on here whenever you want background upload updates again.";
    }

    if (state.permission === "denied") {
      return "Notifications are blocked in browser or app settings. Re-enable them there first, then return here and turn them back on.";
    }

    if (state.permission === "default") {
      return "Inkcreate keeps notifications enabled by default after install. The browser still needs your permission before alerts can appear.";
    }

    return "Background upload retry and sync-complete updates will appear on this device while Inkcreate is installed.";
  }

  enableFeedback(state) {
    if (!state.supported) {
      return "Notifications are not available in this browser.";
    }

    if (state.permission === "granted") {
      return "Notifications are enabled for this device.";
    }

    if (state.permission === "denied") {
      return "The browser blocked notifications. Re-enable them in browser or app settings, then try again here.";
    }

    return "Inkcreate kept notifications turned on, but the browser permission prompt was not completed.";
  }
}
