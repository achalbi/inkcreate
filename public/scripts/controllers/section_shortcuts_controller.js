import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = ["indicator", "link", "rail", "collapseOnDock"];
  static values = {
    collapseThreshold: { type: Number, default: 48 }
  };

  connect() {
    this.sync = this.sync.bind(this);
    this.scheduleSync = this.scheduleSync.bind(this);
    this.topbarElement = document.getElementById("topbar");
    this.activeSectionId = null;
    this.dockedScrollStart = null;
    this.lastDockedState = false;

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
    this.syncDockedState();

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

    if (this.isNearPageBottom()) {
      activeSectionId = this.sections[this.sections.length - 1].id;
    }

    this.setActive(activeSectionId);
  }

  syncDockedState() {
    const railElement = this.hasRailTarget ? this.railTarget : this.element;

    const topbarBottom = this.topbarElement?.getBoundingClientRect().bottom || 0;
    const isDocked = railElement.getBoundingClientRect().top <= topbarBottom + 1;

    if (isDocked && !this.lastDockedState) {
      this.dockedScrollStart = window.scrollY;
    } else if (!isDocked) {
      this.dockedScrollStart = null;
    }

    this.lastDockedState = isDocked;
    this.element.classList.toggle("is-docked", isDocked);
    this.syncCollapsedState(isDocked);
  }

  syncCollapsedState(isDocked) {
    const shouldCollapse = Boolean(
      isDocked &&
      this.dockedScrollStart !== null &&
      window.scrollY - this.dockedScrollStart >= this.collapseThresholdValue
    );

    this.element.classList.toggle("has-collapsed-docked-content", shouldCollapse);

    if (!this.hasCollapseOnDockTarget) {
      return;
    }

    this.collapseOnDockTargets.forEach((target) => {
      target.hidden = false;
      target.classList.toggle("is-collapsed-on-dock", shouldCollapse);
      target.setAttribute("aria-hidden", shouldCollapse ? "true" : "false");
    });
  }

  setActive(activeSectionId) {
    const activeLink = this.linkTargets.find((link) => link.getAttribute("href") === `#${activeSectionId}`) || null;

    if (this.activeSectionId === activeSectionId) {
      this.positionIndicator(activeLink);
      return;
    }

    this.activeSectionId = activeSectionId;

    this.linkTargets.forEach((link) => {
      const isActive = link.getAttribute("href") === `#${activeSectionId}`;

      link.classList.toggle("is-active", isActive);

      if (isActive) {
        link.setAttribute("aria-current", "location");
      } else {
        link.removeAttribute("aria-current");
      }
    });

    this.positionIndicator(activeLink);
  }

  isNearPageBottom() {
    const threshold = 12;
    const viewportBottom = window.scrollY + window.innerHeight;
    const pageBottom = document.documentElement.scrollHeight;

    return viewportBottom >= pageBottom - threshold;
  }

  positionIndicator(activeLink) {
    if (!this.hasIndicatorTarget || !this.hasRailTarget || !activeLink) {
      return;
    }

    const railRect = this.railTarget.getBoundingClientRect();
    const linkRect = activeLink.getBoundingClientRect();
    const x = linkRect.left - railRect.left;

    this.indicatorTarget.style.width = `${linkRect.width}px`;
    this.indicatorTarget.style.transform = `translate3d(${x}px, 0, 0)`;
  }
}
