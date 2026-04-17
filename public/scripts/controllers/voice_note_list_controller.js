import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = ["main", "toggle"];

  static TRANSITION = "max-height 0.32s cubic-bezier(0.22, 1, 0.36, 1), opacity 0.18s ease, transform 0.28s cubic-bezier(0.22, 1, 0.36, 1)";

  connect() {
    this.expanded = false;
    this.mainTargets.forEach((target) => {
      this.resetCollapsedState(target);
    });
    this.syncToggle();
  }

  toggle(event) {
    event.preventDefault();
    this.expanded = !this.expanded;
    this.mainTargets.forEach((target) => {
      if (this.expanded) {
        this.expandTarget(target);
      } else {
        this.collapseTarget(target);
      }
    });
    this.syncToggle();
  }

  syncToggle() {
    this.element.classList.toggle("is-voice-note-list-expanded", this.expanded);

    if (this.hasToggleTarget) {
      const label = this.expanded ? "Collapse voice note details" : "Expand voice note details";
      this.toggleTarget.setAttribute("aria-expanded", this.expanded ? "true" : "false");
      this.toggleTarget.setAttribute("aria-label", label);
      this.toggleTarget.setAttribute("title", label);
      this.toggleTarget.classList.toggle("is-expanded", this.expanded);
    }
  }

  expandTarget(target) {
    target.hidden = false;
    target.setAttribute("aria-hidden", "false");
    target.style.transition = this.constructor.TRANSITION;
    target.style.overflow = "hidden";
    target.style.maxHeight = "0px";
    target.style.opacity = "0";
    target.style.transform = "translateY(-0.3rem)";

    window.requestAnimationFrame(() => {
      target.style.maxHeight = `${target.scrollHeight}px`;
      target.style.opacity = "1";
      target.style.transform = "translateY(0)";
    });

    const cleanup = () => {
      target.style.maxHeight = "";
      target.style.overflow = "";
      target.removeEventListener("transitionend", cleanup);
    };

    target.addEventListener("transitionend", cleanup, { once: true });
  }

  collapseTarget(target) {
    target.hidden = false;
    target.setAttribute("aria-hidden", "true");
    target.style.transition = this.constructor.TRANSITION;
    target.style.overflow = "hidden";
    target.style.maxHeight = `${target.scrollHeight}px`;
    target.style.opacity = "1";
    target.style.transform = "translateY(0)";

    window.requestAnimationFrame(() => {
      target.style.maxHeight = "0px";
      target.style.opacity = "0";
      target.style.transform = "translateY(-0.3rem)";
    });

    const cleanup = () => {
      this.resetCollapsedState(target);
      target.removeEventListener("transitionend", cleanup);
    };

    target.addEventListener("transitionend", cleanup, { once: true });
  }

  resetCollapsedState(target) {
    target.hidden = true;
    target.setAttribute("aria-hidden", "true");
    target.style.transition = "";
    target.style.overflow = "";
    target.style.maxHeight = "";
    target.style.opacity = "";
    target.style.transform = "";
  }
}
