import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = ["label"];

  connect() {
    this.refresh = this.refresh.bind(this);
    window.addEventListener("online", this.refresh);
    window.addEventListener("offline", this.refresh);
    this.refresh();
  }

  disconnect() {
    window.removeEventListener("online", this.refresh);
    window.removeEventListener("offline", this.refresh);
  }

  refresh() {
    if (!this.hasLabelTarget) {
      return;
    }

    this.labelTarget.textContent = navigator.onLine
      ? "Online. Drafts can sync immediately."
      : "Offline. Drafts stay local and will retry later.";
  }
}
