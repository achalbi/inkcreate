import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = ["menu", "toggle", "item"];

  connect() {
    this.isOpen = false;
    this.sync();
  }

  disconnect() {
    this.isOpen = false;
    this.sync();
  }

  toggle(event) {
    event?.preventDefault();
    event?.stopPropagation();

    this.isOpen = !this.isOpen;
    this.sync();
  }

  close() {
    if (!this.isOpen) {
      return;
    }

    this.isOpen = false;
    this.sync();
  }

  openLauncher(event) {
    event?.preventDefault();
    window.dispatchEvent(new CustomEvent("inkcreate:launcher:open"));
  }

  closeOnWindow(event) {
    if (!this.isOpen || this.element.contains(event.target)) {
      return;
    }

    this.close();
  }

  sync() {
    this.element.classList.toggle("is-open", this.isOpen);

    if (this.hasToggleTarget) {
      this.toggleTarget.setAttribute("aria-expanded", this.isOpen ? "true" : "false");
      this.toggleTarget.setAttribute("aria-pressed", this.isOpen ? "true" : "false");
    }

    if (this.hasMenuTarget) {
      this.menuTarget.setAttribute("aria-hidden", this.isOpen ? "false" : "true");
    }

    this.itemTargets.forEach((item) => {
      item.tabIndex = this.isOpen ? 0 : -1;
    });
  }
}
