import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static values = {
    deleteUrl: String,
    confirmMessage: { type: String, default: "Delete this voice note?" }
  };

  async destroy(event) {
    event?.preventDefault();

    if (!this.hasDeleteUrlValue) {
      return;
    }

    if (!window.confirm(this.confirmMessageValue)) {
      return;
    }

    this.element.disabled = true;

    try {
      const response = await fetch(this.deleteUrlValue, {
        method: "DELETE",
        credentials: "same-origin",
        headers: {
          "X-CSRF-Token": this.csrfToken(),
          "Accept": "application/json"
        }
      });

      const payload = await response.json();
      if (!response.ok || payload.ok === false) {
        throw new Error(payload.error || "Voice note could not be deleted.");
      }

      window.location.reload();
    } catch (error) {
      this.element.disabled = false;
      window.alert(error.message || "Voice note could not be deleted right now.");
    }
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || "";
  }
}
