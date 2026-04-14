import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = ["link"];

  connect() {
    this.sync = this.sync.bind(this);
    this.scheduleSync = this.scheduleSync.bind(this);

    this.sections = this.linkTargets.map((link) => {
      const id = link.getAttribute("href")?.replace(/^#/, "");

      return id ? document.getElementById(id) : null;
    }).filter(Boolean);

    window.addEventListener("scroll", this.scheduleSync, { passive: true });
    window.addEventListener("resize", this.scheduleSync);
    window.addEventListener("hashchange", this.scheduleSync);
    this.scheduleSync();
  }

  disconnect() {
    window.removeEventListener("scroll", this.scheduleSync);
    window.removeEventListener("resize", this.scheduleSync);
    window.removeEventListener("hashchange", this.scheduleSync);

    if (this.frameId) {
      window.cancelAnimationFrame(this.frameId);
      this.frameId = null;
    }
  }

  markActive(event) {
    const id = event.currentTarget.getAttribute("href")?.replace(/^#/, "");

    if (!id) {
      return;
    }

    this.setActive(id);
    window.setTimeout(this.scheduleSync, 120);
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
    if (this.sections.length === 0) {
      return;
    }

    const activationLine = this.element.getBoundingClientRect().bottom + 18;
    let activeSectionId = this.sections[0].id;

    this.sections.forEach((section) => {
      if (section.getBoundingClientRect().top <= activationLine) {
        activeSectionId = section.id;
      }
    });

    this.setActive(activeSectionId);
  }

  setActive(activeSectionId) {
    this.linkTargets.forEach((link) => {
      const isActive = link.getAttribute("href") === `#${activeSectionId}`;

      link.classList.toggle("is-active", isActive);

      if (isActive) {
        link.setAttribute("aria-current", "location");
      } else {
        link.removeAttribute("aria-current");
      }
    });
  }
}
