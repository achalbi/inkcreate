import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = [
    "permissionStatus",
    "deviceStatus",
    "helpText",
    "feedback",
    "enableButton",
    "disableButton"
  ];

  static values = {
    disableUrl: String,
    enableUrl: String,
    publicKey: String
  };

  async connect() {
    this.isBusy = false;
    await this.renderState();
  }

  async enable() {
    if (!this.publicKeyValue) {
      await this.renderState("Web Push is not configured for this deployment yet.");
      return;
    }

    this.setBusy(true);

    try {
      const permission = await Notification.requestPermission();
      if (permission !== "granted") {
        await this.renderState("Notification permission was not granted.");
        return;
      }

      const registration = await this.pushRegistration();
      let subscription = await registration.pushManager.getSubscription();

      if (!subscription) {
        subscription = await registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: this.urlBase64ToUint8Array(this.publicKeyValue)
        });
      }

      const payload = subscription.toJSON();

      const response = await fetch(this.enableUrlValue, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken(),
          "Accept": "application/json"
        },
        body: JSON.stringify({
          device: {
            endpoint: payload.endpoint,
            p256dh_key: payload.keys?.p256dh || "",
            auth_key: payload.keys?.auth || ""
          }
        })
      });

      const serverPayload = await response.json();
      if (!response.ok || serverPayload.ok === false) {
        throw new Error(serverPayload.error || "Notifications could not be enabled on this device.");
      }

      await this.renderState("Push notifications are enabled on this device.");
    } catch (error) {
      await this.renderState(error.message || "Notifications could not be enabled on this device.");
    } finally {
      this.setBusy(false);
    }
  }

  async disable() {
    this.setBusy(true);

    try {
      const registration = await this.pushRegistration();
      const subscription = await registration.pushManager.getSubscription();
      if (subscription) {
        await subscription.unsubscribe();
      }

      const response = await fetch(this.disableUrlValue, {
        method: "DELETE",
        credentials: "same-origin",
        headers: {
          "X-CSRF-Token": this.csrfToken(),
          "Accept": "application/json"
        }
      });

      const payload = await response.json();
      if (!response.ok || payload.ok === false) {
        throw new Error(payload.error || "Notifications could not be disabled on this device.");
      }

      await this.renderState("Push notifications are disabled on this device.");
    } catch (error) {
      await this.renderState(error.message || "Notifications could not be disabled on this device.");
    } finally {
      this.setBusy(false);
    }
  }

  async renderState(feedback = "") {
    const support = this.supportState();
    const subscription = support.supported ? await this.currentSubscription() : null;

    if (this.hasPermissionStatusTarget) {
      this.permissionStatusTarget.textContent = support.permissionLabel;
    }

    if (this.hasDeviceStatusTarget) {
      this.deviceStatusTarget.textContent = subscription ? "Push enabled" : "Push disabled";
    }

    if (this.hasHelpTextTarget) {
      this.helpTextTarget.textContent = support.helpText;
    }

    if (this.hasFeedbackTarget) {
      this.feedbackTarget.hidden = feedback.length === 0;
      this.feedbackTarget.textContent = feedback;
    }

    if (this.hasEnableButtonTarget) {
      this.enableButtonTarget.disabled = this.isBusy || !support.supported || support.permission === "denied" || Boolean(subscription);
    }

    if (this.hasDisableButtonTarget) {
      this.disableButtonTarget.disabled = this.isBusy || !support.supported || !subscription;
    }
  }

  supportState() {
    const supported = typeof Notification !== "undefined" && "serviceWorker" in navigator && "PushManager" in window;
    const permission = supported ? Notification.permission : "unsupported";

    return {
      supported,
      permission,
      permissionLabel: supported ? permission.replace(/^./, (value) => value.toUpperCase()) : "Unsupported",
      helpText: supported
        ? "Enable notifications only on devices where you want reminder pushes to appear."
        : "Web Push is unavailable in this browser or on this deployment."
    };
  }

  async currentSubscription() {
    try {
      const registration = await this.pushRegistration();
      return registration.pushManager.getSubscription();
    } catch (_error) {
      return null;
    }
  }

  async pushRegistration() {
    if (window.__inkcreatePushTestRegistration) {
      return window.__inkcreatePushTestRegistration;
    }

    return navigator.serviceWorker.ready;
  }

  setBusy(isBusy) {
    this.isBusy = isBusy;
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || "";
  }

  urlBase64ToUint8Array(base64String) {
    const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
    const normalized = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
    const rawData = window.atob(normalized);
    const outputArray = new Uint8Array(rawData.length);

    for (let index = 0; index < rawData.length; index += 1) {
      outputArray[index] = rawData.charCodeAt(index);
    }

    return outputArray;
  }
}
