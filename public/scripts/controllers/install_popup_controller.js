import { Controller } from "/scripts/vendor/stimulus.js";

// Mobile PWA install popup.
//
// Behavior:
//   * On load, if the current device is a mobile browser, the app is NOT
//     running as an installed PWA, and the user hasn't already installed it,
//     surface a popup nudging them to install.
//   * If the user dismisses it, re-show it five minutes later in the same
//     session (sessionStorage-backed so Turbo nav doesn't reset the clock,
//     but a new tab starts fresh).
//   * If the user installs via the native prompt, stop showing for good.
//
// The popup works in both the Bootstrap-loaded workspace layout and the
// Tailwind-styled landing layout, so we avoid any framework-specific modal
// plumbing and drive show/hide directly through data attributes + inline
// styles supplied by the partial.

const INSTALLED_STORAGE_KEY = "inkcreate.installPrompt.installed";
const DISMISSED_AT_STORAGE_KEY = "inkcreate.installPopup.dismissedAt";
const REPROMPT_INTERVAL_MS = 5 * 60 * 1000; // 5 minutes
const INITIAL_SHOW_DELAY_MS = 2500;         // give the page a moment to paint
const MIN_MOBILE_VIEWPORT_PX = 820;

export default class extends Controller {
  static targets = ["popup", "installButton", "iosSteps", "title", "body"];

  connect() {
    this.deferredPrompt = window.__inkcreateDeferredInstallPrompt || null;
    this.installed = this.readInstalled();
    this.rescheduleTimer = null;
    this.initialTimer = null;

    this.handleInstallAvailable = () => {
      this.deferredPrompt = window.__inkcreateDeferredInstallPrompt || null;

      if (this.isPopupVisible()) {
        // Already showing — just refresh labels so they match what the
        // browser can now do.
        this.renderAvailability();
        return;
      }

      // The deferred prompt may arrive after connect() ran, which means the
      // initial eligibility check said "nothing to offer, skip the popup."
      // Re-evaluate now that we have it.
      this.scheduleNextShow();
    };

    this.handleAppInstalled = () => {
      this.installed = true;
      this.writeInstalled(true);
      this.clearDismissedAt();
      this.hidePopup();
      this.cancelTimers();
    };

    // Cross-tab: if another tab sets the installed flag (via its own
    // successful prompt), react here too instead of surfacing a stale popup.
    this.handleStorage = (event) => {
      if (event.key !== INSTALLED_STORAGE_KEY) {
        return;
      }
      if (event.newValue === "true") {
        this.handleAppInstalled();
      }
    };

    this.handleKeydown = (event) => {
      if (event.key === "Escape" && this.isPopupVisible()) {
        this.dismiss();
      }
    };

    window.addEventListener("inkcreate:install-available", this.handleInstallAvailable);
    window.addEventListener("inkcreate:app-installed", this.handleAppInstalled);
    window.addEventListener("storage", this.handleStorage);
    document.addEventListener("keydown", this.handleKeydown);

    this.scheduleNextShow();
  }

  disconnect() {
    window.removeEventListener("inkcreate:install-available", this.handleInstallAvailable);
    window.removeEventListener("inkcreate:app-installed", this.handleAppInstalled);
    window.removeEventListener("storage", this.handleStorage);
    document.removeEventListener("keydown", this.handleKeydown);
    this.cancelTimers();
  }

  scheduleNextShow() {
    if (!this.shouldShowOnThisDevice()) {
      this.cancelTimers();
      return;
    }

    // If a show is already queued, let it run — resetting on every
    // beforeinstallprompt / install-available would push the popup out by
    // INITIAL_SHOW_DELAY_MS each time the event fires.
    if (this.initialTimer !== null || this.rescheduleTimer !== null) {
      return;
    }

    const dismissedAt = this.readDismissedAt();
    const now = Date.now();
    const elapsed = dismissedAt ? now - dismissedAt : Infinity;

    if (!Number.isFinite(elapsed)) {
      // Never dismissed this session → show after a short paint-settle delay.
      this.initialTimer = window.setTimeout(() => this.showPopup(), INITIAL_SHOW_DELAY_MS);
      return;
    }

    if (elapsed >= REPROMPT_INTERVAL_MS) {
      // The 5-min quiet window has already passed → show right away.
      this.showPopup();
      return;
    }

    // Still inside the quiet window → wait out the remainder.
    const remaining = REPROMPT_INTERVAL_MS - elapsed;
    this.rescheduleTimer = window.setTimeout(() => this.showPopup(), remaining);
  }

  async install() {
    if (this.deferredPrompt) {
      try {
        this.deferredPrompt.prompt();
        const choice = await this.deferredPrompt.userChoice;
        this.deferredPrompt = null;
        window.__inkcreateDeferredInstallPrompt = null;

        if (choice?.outcome === "accepted") {
          this.installed = true;
          this.writeInstalled(true);
          this.clearDismissedAt();
          this.hidePopup();
          this.cancelTimers();
          return;
        }

        // User rejected the native prompt — treat like a dismissal so we
        // don't immediately re-prompt.
        this.dismiss();
        return;
      } catch (_error) {
        // Fall through to the iOS/manual path on any prompt failure.
      }
    }

    // No deferred prompt available — surface the iOS "Add to Home Screen"
    // instructions if this looks like iOS Safari, otherwise just dismiss.
    if (this.isIosSafari() && this.hasIosStepsTarget) {
      this.iosStepsTarget.hidden = false;
      if (this.hasInstallButtonTarget) {
        this.installButtonTarget.hidden = true;
      }
      return;
    }

    this.dismiss();
  }

  dismiss() {
    this.writeDismissedAt(Date.now());
    this.hidePopup();

    // Queue the next re-show in five minutes.
    this.cancelTimers();
    this.rescheduleTimer = window.setTimeout(() => this.showPopup(), REPROMPT_INTERVAL_MS);
  }

  showPopup() {
    if (!this.shouldShowOnThisDevice()) {
      this.hidePopup();
      return;
    }

    if (!this.hasPopupTarget) {
      return;
    }

    this.renderAvailability();
    this.popupTarget.hidden = false;
    this.popupTarget.dataset.visible = "true";
    document.body?.classList.add("install-popup-open");

    // Clear the pending-show timer bookkeeping so a later scheduleNextShow()
    // (e.g. after inkcreate:install-available fires while visible) can queue
    // again if the user dismisses.
    this.initialTimer = null;
    this.rescheduleTimer = null;

    if (this.hasInstallButtonTarget) {
      // Defer focus so animation doesn't fight the browser's scroll-into-view.
      window.setTimeout(() => {
        if (this.isPopupVisible() && this.hasInstallButtonTarget) {
          try {
            this.installButtonTarget.focus({ preventScroll: true });
          } catch (_error) {
            // Some older engines don't accept options; ignore focus failures.
          }
        }
      }, 60);
    }
  }

  hidePopup() {
    if (!this.hasPopupTarget) {
      return;
    }

    this.popupTarget.hidden = true;
    this.popupTarget.dataset.visible = "false";
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

  renderAvailability() {
    const iosSafari = this.isIosSafari();

    if (this.hasInstallButtonTarget) {
      this.installButtonTarget.textContent = iosSafari && !this.deferredPrompt
        ? "Show install steps"
        : "Install app";
    }

    if (this.hasBodyTarget) {
      this.bodyTarget.textContent = iosSafari && !this.deferredPrompt
        ? "Add Inkcreate to your Home Screen from Safari's Share menu for faster capture and offline access."
        : "Install Inkcreate on your phone for faster launch, app-like navigation, and offline shell access.";
    }
  }

  cancelTimers() {
    if (this.initialTimer !== null) {
      window.clearTimeout(this.initialTimer);
      this.initialTimer = null;
    }

    if (this.rescheduleTimer !== null) {
      window.clearTimeout(this.rescheduleTimer);
      this.rescheduleTimer = null;
    }
  }

  // ---------- eligibility checks ----------

  shouldShowOnThisDevice() {
    if (typeof window === "undefined") {
      return false;
    }

    if (this.installed || this.readInstalled()) {
      return false;
    }

    if (this.isStandalone()) {
      return false;
    }

    if (!this.isMobileBrowser()) {
      return false;
    }

    // Only offer the popup when the browser can actually do something useful:
    // either a native prompt is available (Android Chrome / Edge) or this is
    // iOS Safari where the manual "Add to Home Screen" path works.
    return Boolean(this.deferredPrompt) || this.isIosSafari();
  }

  isStandalone() {
    try {
      if (window.matchMedia?.("(display-mode: standalone)")?.matches) {
        return true;
      }
    } catch (_error) {
      // matchMedia can throw in very old browsers; treat as non-standalone.
    }

    if (window.navigator.standalone === true) {
      return true;
    }

    return false;
  }

  isMobileBrowser() {
    const userAgent = window.navigator.userAgent || "";
    const mobileUa = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini|Mobile/i.test(userAgent);

    if (mobileUa) {
      return true;
    }

    // Fallback: iPad on iPadOS 13+ reports a desktop UA but has touch points.
    const platform = window.navigator.platform || "";
    const maxTouchPoints = window.navigator.maxTouchPoints || 0;
    if (platform === "MacIntel" && maxTouchPoints > 1) {
      return true;
    }

    // Final fallback: narrow-viewport + coarse-pointer devices look mobile.
    const narrowViewport = typeof window.innerWidth === "number" && window.innerWidth <= MIN_MOBILE_VIEWPORT_PX;
    const coarsePointer = Boolean(window.matchMedia?.("(pointer: coarse)")?.matches);
    return narrowViewport && coarsePointer;
  }

  isIosSafari() {
    const userAgent = window.navigator.userAgent || "";
    const platform = window.navigator.platform || "";
    const maxTouchPoints = window.navigator.maxTouchPoints || 0;
    const appleMobile = /iPad|iPhone|iPod/.test(userAgent) || (platform === "MacIntel" && maxTouchPoints > 1);
    const isWebKit = /AppleWebKit/i.test(userAgent);
    const nonSafariIos = /CriOS|FxiOS|EdgiOS|OPiOS|DuckDuckGo/i.test(userAgent);
    return appleMobile && isWebKit && !nonSafariIos;
  }

  // ---------- storage helpers ----------

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
      const raw = window.sessionStorage?.getItem(DISMISSED_AT_STORAGE_KEY);
      if (!raw) {
        return null;
      }
      const parsed = Number.parseInt(raw, 10);
      return Number.isFinite(parsed) ? parsed : null;
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
