import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = ["rail"];

  connect() {
    this.scheduleSync = this.scheduleSync.bind(this);
    this.sync = this.sync.bind(this);
    this.topbarElement = document.getElementById("topbar");
    this.lastDockedState = null;

    window.addEventListener("scroll", this.scheduleSync, { passive: true });
    window.addEventListener("resize", this.scheduleSync);
    this.scheduleSync();
  }

  disconnect() {
    window.removeEventListener("scroll", this.scheduleSync);
    window.removeEventListener("resize", this.scheduleSync);

    if (this.frameId) {
      window.cancelAnimationFrame(this.frameId);
      this.frameId = null;
    }
  }

  scheduleSync() {
    if (this.frameId) {
      return;
    }

    this.frameId = window.requestAnimationFrame(() => {
      this.frameId = null;
      this.sync();
    });
  }

  sync() {
    const railElement = this.hasRailTarget ? this.railTarget : this.element;
    const topbarBottom = this.topbarElement?.getBoundingClientRect().bottom || 0;
    const isDocked = railElement.getBoundingClientRect().top <= topbarBottom + 1;

    if (this.lastDockedState === isDocked) {
      return;
    }

    this.lastDockedState = isDocked;
    this.element.classList.toggle("is-docked", isDocked);
  }
}
