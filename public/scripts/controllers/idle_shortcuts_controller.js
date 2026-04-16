import { Controller } from "/scripts/vendor/stimulus.js";

const INTERACTION_EVENTS = ["pointerdown", "pointermove", "touchstart", "scroll", "focusin"];
const IDLE_RETRY_MS = 2000;

export default class extends Controller {
  static targets = ["overlay"];

  static values = {
    idleMs: { type: Number, default: 60000 },
    storageKey: String
  };

  connect() {
    this.visible = false;

    this.boundResetTimer = this.resetTimer.bind(this);
    this.boundKeydown = this.handleKeydown.bind(this);
    this.boundVisibilityChange = this.handleVisibilityChange.bind(this);
    this.boundStorage = this.handleStorage.bind(this);

    INTERACTION_EVENTS.forEach((eventName) => {
      window.addEventListener(eventName, this.boundResetTimer, { passive: true });
    });
    document.addEventListener("keydown", this.boundKeydown);
    document.addEventListener("visibilitychange", this.boundVisibilityChange);
    window.addEventListener("storage", this.boundStorage);

    this.ensureLastActivityAt();
    this.scheduleFromLastActivity();
  }

  disconnect() {
    this.clearTimer();

    if (!this.boundResetTimer) {
      return;
    }

    INTERACTION_EVENTS.forEach((eventName) => {
      window.removeEventListener(eventName, this.boundResetTimer);
    });
    document.removeEventListener("keydown", this.boundKeydown);
    document.removeEventListener("visibilitychange", this.boundVisibilityChange);
    window.removeEventListener("storage", this.boundStorage);
  }

  continue() {
    this.recordActivity();
    this.hide();
  }

  hideImmediately() {
    this.recordActivity();
    this.hide({ immediate: true });
  }

  backdropClick(event) {
    if (event.target === this.overlayTarget) {
      this.recordActivity();
      this.hide();
    }
  }

  followLink() {
    this.recordActivity();
    this.hide({ immediate: true });
  }

  runCommand(event) {
    const { idleShortcutsCommand: command, idleShortcutsModalId: modalId, idleShortcutsSelector: selector } = event.currentTarget.dataset;

    this.recordActivity();
    this.hide({ immediate: true });

    if (!command) {
      return;
    }

    window.setTimeout(() => {
      switch (command) {
        case "open-task-quick-add":
          window.dispatchEvent(new CustomEvent("task-manager:open-quick-add"));
          break;
        case "open-modal":
          this.openModal(modalId);
          break;
        case "click-selector":
          document.querySelector(selector)?.click();
          break;
        default:
          break;
      }
    }, 40);
  }

  resetTimer() {
    if (this.visible) {
      return;
    }

    this.recordActivity();
    this.scheduleFromLastActivity();
  }

  scheduleFromLastActivity() {
    if (this.visible) {
      return;
    }

    this.clearTimer();
    const remainingMs = Math.max(this.idleMsValue - this.elapsedSinceLastActivity(), 0);
    this.timer = window.setTimeout(() => this.handleIdle(), remainingMs);
  }

  handleKeydown(event) {
    if (this.visible && event.key === "Escape") {
      this.recordActivity();
      this.hide();
      return;
    }

    this.resetTimer();
  }

  handleVisibilityChange() {
    if (document.hidden) {
      this.clearTimer();
      return;
    }

    this.ensureLastActivityAt();
    this.scheduleFromLastActivity();
  }

  handleStorage(event) {
    if (event.key !== this.activityStorageKey()) {
      return;
    }

    if (this.visible && this.elapsedSinceLastActivity() < this.idleMsValue) {
      this.hide({ immediate: true });
      return;
    }

    this.scheduleFromLastActivity();
  }

  handleIdle() {
    if (this.visible) {
      return;
    }

    if (!this.canShow()) {
      this.clearTimer();
      this.timer = window.setTimeout(() => this.handleIdle(), IDLE_RETRY_MS);
      return;
    }

    this.show();
  }

  show() {
    this.overlayTarget.style.display = "flex";
    this.overlayTarget.classList.remove("idle-shortcuts--exiting");
    window.requestAnimationFrame(() => this.overlayTarget.classList.add("is-visible"));
    document.body.classList.add("idle-shortcuts-open");
    this.visible = true;
  }

  hide({ immediate = false } = {}) {
    if (!this.visible) {
      return;
    }

    const finish = () => {
      this.overlayTarget.style.display = "none";
      this.overlayTarget.classList.remove("is-visible");
      this.overlayTarget.classList.remove("idle-shortcuts--exiting");
    };

    this.visible = false;
    document.body.classList.remove("idle-shortcuts-open");

    if (immediate) {
      finish();
      this.scheduleFromLastActivity();
      return;
    }

    this.overlayTarget.classList.add("idle-shortcuts--exiting");
    window.setTimeout(() => {
      finish();
      this.scheduleFromLastActivity();
    }, 220);
  }

  clearTimer() {
    if (this.timer) {
      window.clearTimeout(this.timer);
      this.timer = null;
    }
  }

  ensureLastActivityAt() {
    if (this.lastActivityAt()) {
      return;
    }

    this.recordActivity();
  }

  recordActivity() {
    localStorage.setItem(this.activityStorageKey(), String(Date.now()));
  }

  lastActivityAt() {
    const raw = localStorage.getItem(this.activityStorageKey());
    const parsed = Number.parseInt(raw || "", 10);
    return Number.isFinite(parsed) ? parsed : null;
  }

  elapsedSinceLastActivity() {
    const lastActivityAt = this.lastActivityAt();
    if (!lastActivityAt) {
      return 0;
    }

    return Math.max(Date.now() - lastActivityAt, 0);
  }

  canShow() {
    if (document.hidden) {
      return false;
    }

    if (document.querySelector(".modal.show")) {
      return false;
    }

    const onboarding = document.querySelector(".onboarding-backdrop");
    if (onboarding && onboarding.style.display !== "none" && onboarding.style.display !== "") {
      return false;
    }

    const activeElement = document.activeElement;
    if (activeElement && activeElement !== document.body) {
      const focusedField = activeElement.matches("input, textarea, select, [contenteditable='true'], [contenteditable='']");
      if (focusedField) {
        return false;
      }
    }

    return true;
  }

  openModal(modalId) {
    if (!modalId) {
      return;
    }

    const element = document.getElementById(modalId);
    if (!element || !window.bootstrap?.Modal) {
      return;
    }

    window.bootstrap.Modal.getOrCreateInstance(element).show();
  }

  activityStorageKey() {
    return `inkcreate:idle-shortcuts:${this.storageKeyValue || "workspace"}:last-activity-at`;
  }
}
