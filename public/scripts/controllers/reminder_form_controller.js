import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = ["panel"];

  toggle() {
    if (!this.hasPanelTarget) {
      return;
    }

    this.panelTarget.hidden = !this.panelTarget.hidden;
  }
}
