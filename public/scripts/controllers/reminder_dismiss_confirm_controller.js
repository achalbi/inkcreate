import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = ["modal", "form", "title", "message"];

  connect() {
    this.defaultTitle = this.hasTitleTarget ? this.titleTarget.textContent.trim() : "Dismiss reminder?";
    this.defaultMessage = this.hasMessageTarget ? this.messageTarget.textContent.trim() : "This reminder will move to reminder history and stop sending notifications.";
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
    const dismissUrl = trigger?.dataset?.reminderDismissUrl;

    if (!dismissUrl || !this.hasModalTarget || !this.hasFormTarget) {
      return;
    }

    const reminderTitle = trigger.dataset.reminderDismissTitle || "This reminder";

    this.formTarget.action = dismissUrl;

    if (this.hasTitleTarget) {
      this.titleTarget.textContent = this.defaultTitle;
    }

    if (this.hasMessageTarget) {
      this.messageTarget.textContent = `"${reminderTitle}" will move to reminder history and stop sending notifications.`;
    }

    this.showModal();
  }

  reset() {
    if (this.hasFormTarget) {
      this.formTarget.action = "/reminders";
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
