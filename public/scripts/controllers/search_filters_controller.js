import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  connect() {
    this.element.querySelectorAll("select").forEach((select) => {
      select.addEventListener("change", () => this.element.requestSubmit());
    });
  }
}
