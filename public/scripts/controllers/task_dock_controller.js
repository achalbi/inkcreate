import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = ["collapseOnDock"];
  static values = {
    collapseThreshold: { type: Number, default: 48 }
  };

  static DOCK_ENTER_OFFSET_PX = 1;
  static DOCK_EXIT_OFFSET_PX = 14;

  connect() {
    this.scheduleSync = this.scheduleSync.bind(this);
    this.sync = this.sync.bind(this);
    this.topbarElement = document.getElementById("topbar");
    this.lastDockedState = false;
    this.isCollapsedOnDock = false;
    this.insertSentinel();

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

    if (this.sentinelElement?.isConnected) {
      this.sentinelElement.remove();
    }

    this.sentinelElement = null;
  }

  insertSentinel() {
    if (this.sentinelElement?.isConnected) {
      return;
    }

    const sentinel = document.createElement("div");
    sentinel.className = "task-index-actions__dock-sentinel";
    sentinel.setAttribute("aria-hidden", "true");
    this.element.before(sentinel);
    this.sentinelElement = sentinel;
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
  }

  syncDockedState() {
    if (!this.sentinelElement) {
      return;
    }

    const topbarBottom = this.topbarElement?.getBoundingClientRect().bottom || 0;
    const sentinelTop = this.sentinelElement.getBoundingClientRect().top;
    const dockedBoundary = this.lastDockedState
      ? topbarBottom + this.constructor.DOCK_EXIT_OFFSET_PX
      : topbarBottom + this.constructor.DOCK_ENTER_OFFSET_PX;
    const isDocked = sentinelTop <= dockedBoundary;

    if (!isDocked) {
      this.isCollapsedOnDock = false;
    }

    this.lastDockedState = isDocked;
    this.element.classList.toggle("is-docked", isDocked);
    this.syncCollapsedState(isDocked, sentinelTop, topbarBottom);
  }

  syncCollapsedState(isDocked, sentinelTop, topbarBottom) {
    const dockDepth = topbarBottom - sentinelTop;
    const shouldCollapse = Boolean(
      isDocked &&
      (
        this.isCollapsedOnDock ||
        dockDepth >= this.collapseThresholdValue
      )
    );

    this.isCollapsedOnDock = shouldCollapse;
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
}
