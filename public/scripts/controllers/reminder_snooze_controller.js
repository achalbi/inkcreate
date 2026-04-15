import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = ["modal", "form", "title", "message"];

  connect() {
    this.defaultTitle = this.hasTitleTarget ? this.titleTarget.textContent.trim() : "Snooze reminder?";
    this.defaultMessage = this.hasMessageTarget ? this.messageTarget.textContent.trim() : "Choose how long to snooze this reminder.";
    this.defaultAction = this.hasFormTarget ? (this.formTarget.getAttribute("action") || "/reminders") : "/reminders";
    this.boundReset = this.reset.bind(this);

    if (this.hasModalTarget) {
      this.modalTarget.addEventListener("hidden.bs.modal", this.boundReset);
    }
  }

  disconnect() {
    if (this.hasModalTarget) {
      this.modalTarget.removeEventListener("hidden.bs.modal", this.boundReset);
    }
  }

  open(event) {
    event?.preventDefault();

    const trigger = event?.currentTarget;
    const snoozeUrl = trigger?.dataset?.reminderSnoozeUrl;

    if (!snoozeUrl || !this.hasModalTarget || !this.hasFormTarget) {
      return;
    }

    const reminderTitle = trigger.dataset.reminderSnoozeTitle || "This reminder";

    this.formTarget.action = snoozeUrl;

    if (this.hasTitleTarget) {
      this.titleTarget.textContent = this.defaultTitle;
    }

    if (this.hasMessageTarget) {
      this.messageTarget.textContent = `Choose how long to snooze "${reminderTitle}".`;
    }

    this.showModal();
  }

  reset() {
    if (this.hasFormTarget) {
      this.formTarget.action = this.defaultAction;
    }

    if (this.hasTitleTarget) {
      this.titleTarget.textContent = this.defaultTitle;
    }

    if (this.hasMessageTarget) {
      this.messageTarget.textContent = this.defaultMessage;
    }
  }

  showModal() {
    const ModalClass = window.bootstrap?.Modal;
    if (!ModalClass) return;

    const modal = ModalClass.getInstance(this.modalTarget) || ModalClass.getOrCreateInstance(this.modalTarget);
    modal.show();
  }
}
