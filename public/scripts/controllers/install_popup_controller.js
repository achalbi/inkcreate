import { Controller } from "/scripts/vendor/stimulus.js";

const INSTALLED_STORAGE_KEY = "inkcreate.installPrompt.installed";
const DISMISSED_AT_STORAGE_KEY = "inkcreate.installPopup.dismissedAt";
const DEFAULT_REPROMPT_INTERVAL_MS = 5 * 60 * 1000;
const DEFAULT_INITIAL_SHOW_DELAY_MS = 0;
const MIN_MOBILE_VIEWPORT_PX = 820;

export default class extends Controller {
  static targets = ["popup", "installButton", "iosSteps", "title", "body"];

  connect() {
    this.element.installPopupController = this;
    this.deferredPrompt = window.__inkcreateDeferredInstallPrompt || null;
    this.installed = this.readInstalled();
    this.showTimer = null;
    this.focusTimer = null;
    this.pendingShowAt = null;

    this.handleInstallAvailable = () => {
      this.deferredPrompt = window.__inkcreateDeferredInstallPrompt || null;

      if (this.isPopupVisible()) {
        this.renderAvailability();
        return;
      }

      this.scheduleNextShow();
    };

    this.handleAppInstalled = () => {
      this.markInstalled();
    };

    this.handleStorage = (event) => {
      if (event.key === INSTALLED_STORAGE_KEY && event.newValue === "true") {
        this.markInstalled();
      }
    };

    this.handleKeydown = (event) => {
      if (event.key === "Escape" && this.isPopupVisible()) {
        this.dismiss();
      }
    };

    this.handleBeforeCache = () => {
      this.cancelTimers();
      this.hidePopup();
    };

    window.addEventListener("inkcreate:install-available", this.handleInstallAvailable);
    window.addEventListener("inkcreate:app-installed", this.handleAppInstalled);
    window.addEventListener("storage", this.handleStorage);
    document.addEventListener("keydown", this.handleKeydown);
    document.addEventListener("turbo:before-cache", this.handleBeforeCache);

    this.scheduleNextShow();
  }

  disconnect() {
    delete this.element.installPopupController;
    window.removeEventListener("inkcreate:install-available", this.handleInstallAvailable);
    window.removeEventListener("inkcreate:app-installed", this.handleAppInstalled);
    window.removeEventListener("storage", this.handleStorage);
    document.removeEventListener("keydown", this.handleKeydown);
    document.removeEventListener("turbo:before-cache", this.handleBeforeCache);
    this.cancelTimers();
    this.hidePopup();
  }

  scheduleNextShow() {
    this.deferredPrompt = window.__inkcreateDeferredInstallPrompt || this.deferredPrompt || null;

    if (!this.shouldShowOnThisDevice()) {
      this.cancelTimers();
      this.hidePopup();
      return;
    }

    if (this.isPopupVisible()) {
      this.renderAvailability();
      return;
    }

    const dismissedAt = this.readDismissedAt();

    if (dismissedAt === null) {
      this.queueShow(this.initialShowDelayMs());
      return;
    }

    const elapsed = Date.now() - dismissedAt;
    if (elapsed >= this.repromptIntervalMs()) {
      this.queueShow(0);
      return;
    }

    this.queueShow(this.repromptIntervalMs() - elapsed);
  }

  async install() {
    if (this.deferredPrompt) {
      try {
        this.deferredPrompt.prompt();
        const choice = await this.deferredPrompt.userChoice;
        this.deferredPrompt = null;
        window.__inkcreateDeferredInstallPrompt = null;

        if (choice?.outcome === "accepted") {
          this.markInstalled();
          return;
        }

        this.dismiss();
        return;
      } catch (_error) {
        this.deferredPrompt = null;
        window.__inkcreateDeferredInstallPrompt = null;
      }
    }

    if (this.isIosSafari() && this.hasIosStepsTarget) {
      this.renderAvailability({ revealIosSteps: true });
      return;
    }

    this.dismiss();
  }

  dismiss() {
    this.writeDismissedAt(Date.now());
    this.hidePopup();
    this.queueShow(this.repromptIntervalMs());
  }

  dismissOnBackdrop(event) {
    if (event.target === this.popupTarget) {
      this.dismiss();
    }
  }

  initialShowDelayMs() {
    return DEFAULT_INITIAL_SHOW_DELAY_MS;
  }

  repromptIntervalMs() {
    return DEFAULT_REPROMPT_INTERVAL_MS;
  }

  showPopup() {
    this.pendingShowAt = null;
    this.showTimer = null;

    if (!this.shouldShowOnThisDevice() || !this.hasPopupTarget) {
      this.hidePopup();
      return;
    }

    this.renderAvailability();
    this.popupTarget.hidden = false;
    this.popupTarget.dataset.visible = "true";
    this.popupTarget.setAttribute("aria-hidden", "false");
    document.body?.classList.add("install-popup-open");

    if (!this.hasInstallButtonTarget) {
      return;
    }

    this.focusTimer = window.setTimeout(() => {
      this.focusTimer = null;

      if (!this.isPopupVisible() || this.installButtonTarget.hidden) {
        return;
      }

      try {
        this.installButtonTarget.focus({ preventScroll: true });
      } catch (_error) {
        this.installButtonTarget.focus();
      }
    }, 60);
  }

  hidePopup() {
    if (this.focusTimer !== null) {
      window.clearTimeout(this.focusTimer);
      this.focusTimer = null;
    }

    if (!this.hasPopupTarget) {
      document.body?.classList.remove("install-popup-open");
      return;
    }

    this.popupTarget.hidden = true;
    this.popupTarget.dataset.visible = "false";
    this.popupTarget.setAttribute("aria-hidden", "true");
    document.body?.classList.remove("install-popup-open");

    if (this.hasIosStepsTarget) {
      this.iosStepsTarget.hidden = true;
    }

    if (this.hasInstallButtonTarget) {
      this.installButtonTarget.hidden = false;
    }
  }

  isPopupVisible() {
    return this.hasPopupTarget && this.popupTarget.dataset.visible === "true";
  }

  renderAvailability({ revealIosSteps = false } = {}) {
    const hasDeferredPrompt = Boolean(this.deferredPrompt);
    const iosSafari = this.isIosSafari() && !hasDeferredPrompt;

    if (this.hasTitleTarget) {
      this.titleTarget.textContent = iosSafari
        ? "Add Inkcreate to your Home Screen"
        : "Install Inkcreate on your device";
    }

    if (this.hasBodyTarget) {
      this.bodyTarget.textContent = iosSafari
        ? "Open Safari's Share menu and add Inkcreate to your Home Screen for faster launch and app-like navigation."
        : "Install Inkcreate for faster launch, app-like navigation, and offline shell access.";
    }

    if (this.hasInstallButtonTarget) {
      this.installButtonTarget.textContent = iosSafari ? "Show install steps" : "Install app";
      this.installButtonTarget.hidden = false;
    }

    if (this.hasIosStepsTarget) {
      this.iosStepsTarget.hidden = !(iosSafari && revealIosSteps);
    }
  }

  cancelTimers() {
    if (this.showTimer !== null) {
      window.clearTimeout(this.showTimer);
      this.showTimer = null;
    }

    if (this.focusTimer !== null) {
      window.clearTimeout(this.focusTimer);
      this.focusTimer = null;
    }

    this.pendingShowAt = null;
  }

  queueShow(delayMs) {
    const delay = Math.max(0, Number(delayMs) || 0);
    const showAt = Date.now() + delay;

    if (this.pendingShowAt !== null && this.pendingShowAt <= showAt) {
      return;
    }

    if (this.showTimer !== null) {
      window.clearTimeout(this.showTimer);
      this.showTimer = null;
    }

    this.pendingShowAt = showAt;

    if (delay === 0) {
      this.showPopup();
      return;
    }

    this.showTimer = window.setTimeout(() => this.showPopup(), delay);
  }

  markInstalled() {
    this.installed = true;
    this.writeInstalled(true);
    this.clearDismissedAt();
    this.cancelTimers();
    this.hidePopup();
  }

  shouldShowOnThisDevice() {
    if (typeof window === "undefined") {
      return false;
    }

    if (this.installedPreferenceActive()) {
      return false;
    }

    if (this.isStandalone()) {
      return false;
    }

    if (!this.isMobileBrowser()) {
      return false;
    }

    return Boolean(this.deferredPrompt) || this.isIosSafari();
  }

  installedPreferenceActive() {
    if (!this.installed && !this.readInstalled()) {
      return false;
    }

    if (this.isStandalone()) {
      return true;
    }

    if (this.deferredPrompt) {
      this.installed = false;
      this.writeInstalled(false);
      return false;
    }

    return true;
  }

  isStandalone() {
    try {
      if (window.matchMedia?.("(display-mode: standalone)")?.matches) {
        return true;
      }
    } catch (_error) {
      // Ignore matchMedia failures and treat the page as browser mode.
    }

    return window.navigator.standalone === true;
  }

  isMobileBrowser() {
    const userAgent = window.navigator.userAgent || "";
    if (/Android|iPhone|iPad|iPod|webOS|BlackBerry|IEMobile|Opera Mini|Mobile/i.test(userAgent)) {
      return true;
    }

    const platform = window.navigator.platform || "";
    const maxTouchPoints = window.navigator.maxTouchPoints || 0;
    if (platform === "MacIntel" && maxTouchPoints > 1) {
      return true;
    }

    try {
      const narrowViewport = typeof window.innerWidth === "number" && window.innerWidth <= MIN_MOBILE_VIEWPORT_PX;
      const coarsePointer = window.matchMedia?.("(pointer: coarse)")?.matches === true;
      return narrowViewport && coarsePointer;
    } catch (_error) {
      return false;
    }
  }

  isIosSafari() {
    const userAgent = window.navigator.userAgent || "";
    const platform = window.navigator.platform || "";
    const maxTouchPoints = window.navigator.maxTouchPoints || 0;
    const appleMobileDevice = /iPad|iPhone|iPod/.test(userAgent) || (platform === "MacIntel" && maxTouchPoints > 1);
    const safariWebKit = /AppleWebKit/i.test(userAgent);
    const excludedBrowsers = /CriOS|FxiOS|EdgiOS|OPiOS|DuckDuckGo/i.test(userAgent);
    return appleMobileDevice && safariWebKit && !excludedBrowsers;
  }

  readInstalled() {
    try {
      return window.localStorage?.getItem(INSTALLED_STORAGE_KEY) === "true";
    } catch (_error) {
      return false;
    }
  }

  writeInstalled(installed) {
    try {
      if (installed) {
        window.localStorage?.setItem(INSTALLED_STORAGE_KEY, "true");
      } else {
        window.localStorage?.removeItem(INSTALLED_STORAGE_KEY);
      }
    } catch (_error) {
      // Ignore storage failures and keep the app usable.
    }
  }

  readDismissedAt() {
    try {
      const rawValue = window.sessionStorage?.getItem(DISMISSED_AT_STORAGE_KEY);
      if (!rawValue) {
        return null;
      }

      const timestamp = Number.parseInt(rawValue, 10);
      return Number.isFinite(timestamp) ? timestamp : null;
    } catch (_error) {
      return null;
    }
  }

  writeDismissedAt(timestamp) {
    try {
      window.sessionStorage?.setItem(DISMISSED_AT_STORAGE_KEY, String(timestamp));
    } catch (_error) {
      // Ignore storage failures and keep the app usable.
    }
  }

  clearDismissedAt() {
    try {
      window.sessionStorage?.removeItem(DISMISSED_AT_STORAGE_KEY);
    } catch (_error) {
      // Ignore storage failures and keep the app usable.
    }
  }
}
