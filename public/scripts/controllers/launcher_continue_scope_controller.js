import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = ["option"];
  static values = { url: String, csrf: String };

  select(event) {
    const button = event.currentTarget;
    const scope = button?.dataset?.scopeValue;
    if (!scope) {
      return;
    }

    const current = this.activeScope();
    if (current === scope) {
      return;
    }

    this.setActive(scope);
    this.persist(scope).catch(() => {
      this.setActive(current);
    });
  }

  activeScope() {
    const active = this.optionTargets.find((option) => option.classList.contains("is-active"));
    return active?.dataset?.scopeValue || null;
  }

  setActive(scope) {
    this.optionTargets.forEach((option) => {
      const isActive = option.dataset.scopeValue === scope;
      option.classList.toggle("is-active", isActive);
      option.setAttribute("aria-checked", isActive ? "true" : "false");
    });
  }

  async persist(scope) {
    if (!this.hasUrlValue || !this.urlValue) {
      return;
    }

    const body = new FormData();
    body.append("_method", "patch");
    body.append("app_setting[continue_scope]", scope);
    if (this.hasCsrfValue && this.csrfValue) {
      body.append("authenticity_token", this.csrfValue);
    }

    const response = await fetch(this.urlValue, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "X-CSRF-Token": this.csrfValue || ""
      },
      body,
      credentials: "same-origin"
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
  }
}
