import { Controller } from "/scripts/vendor/stimulus.js";

const SECTION_OPEN_DELAY_MS = 220;
const SECTION_SCROLL_SETTLE_DELAY_MS = 260;

export default class extends Controller {
  static targets = ["menu", "toggle", "item"];

  static values = {
    photosSectionId: String,
    cameraInputId: String,
    cameraButtonId: String,
    voiceSectionId: String,
    todoSectionId: String,
    scanSectionId: String,
    locationSectionId: String,
    locationInputId: String,
    contactSectionId: String,
    contactButtonId: String
  };

  connect() {
    this.isOpen = false;
    this.sync();
    this.autoOpenFromUrl();
  }

  autoOpenFromUrl() {
    let open;
    try {
      open = new URLSearchParams(window.location.search).get("open");
    } catch (_error) {
      return;
    }
    if (!open) {
      return;
    }

    const panelMethod = {
      camera: "openCamera",
      voice: "openVoiceNote",
      todo: "openTodo",
      scan: "openScan",
      location: "openLocation",
      contact: "openContact"
    }[open];

    if (!panelMethod || typeof this[panelMethod] !== "function") {
      this.stripOpenParam();
      return;
    }

    window.setTimeout(() => {
      this[panelMethod]();
      this.stripOpenParam();
    }, 80);
  }

  stripOpenParam() {
    try {
      const url = new URL(window.location.href);
      if (!url.searchParams.has("open")) {
        return;
      }
      url.searchParams.delete("open");
      const next = url.pathname + (url.searchParams.toString() ? `?${url.searchParams}` : "") + url.hash;
      window.history.replaceState({}, "", next);
    } catch (_error) {
      // ignore
    }
  }

  disconnect() {
    this.isOpen = false;
    this.sync();
    this.clearScrollSpacer();
  }

  toggle(event) {
    event?.preventDefault();
    event?.stopPropagation();

    this.isOpen = !this.isOpen;
    this.sync();
  }

  close() {
    if (!this.isOpen) {
      return;
    }

    this.isOpen = false;
    this.sync();
  }

  closeOnWindow(event) {
    if (!this.isOpen || this.element.contains(event.target)) {
      return;
    }

    this.close();
  }

  openCamera(event) {
    event?.preventDefault();
    this.close();
    this.openCameraInput();
  }

  openGallery(event) {
    event?.preventDefault();
    this.close();

    this.runSectionAction(this.photosSectionIdValue, {
      selector: "[data-action*='photo-capture#chooseFromGallery']",
      callback: (button) => button.click()
    });
  }

  openVoiceNote(event) {
    event?.preventDefault();
    this.close();

    this.runSectionAction(this.voiceSectionIdValue, {
      selector: "[data-voice-recorder-target='startButton']",
      callback: (button) => button.click()
    });
  }

  openTodo(event) {
    event?.preventDefault();
    this.close();

    this.runSectionAction(this.todoSectionIdValue, {
      selector: ".todo-list-composer__input",
      callback: (input) => {
        input.focus();

        if (typeof input.select === "function") {
          input.select();
        }
      }
    });
  }

  openLocation(event) {
    event?.preventDefault();
    this.close();

    this.runSectionAction(this.locationSectionIdValue, {
      selector: this.locationInputSelector(),
      alignTop: true,
      updateHash: true,
      callback: (input) => {
        input.focus({ preventScroll: true });
      }
    });
  }

  openContact(event) {
    event?.preventDefault();
    this.close();

    this.runSectionAction(this.contactSectionIdValue, {
      selector: this.contactButtonSelector(),
      alignTop: true,
      updateHash: true,
      callback: (button) => button.click()
    });
  }

  openScan(event) {
    event?.preventDefault();
    this.close();

    this.runSectionAction(this.scanSectionIdValue, {
      selector: "[data-action*='document-capture#open']",
      callback: (button) => button.click()
    });
  }

  runSectionAction(sectionId, { selector, callback, updateHash = false, alignTop = false }) {
    if (!sectionId) {
      return;
    }

    const section = document.getElementById(sectionId);
    if (!(section instanceof HTMLElement)) {
      return;
    }

    const delay = this.ensureExpanded(section);
    this.scrollSection(section, { alignTop, behavior: "smooth" });
    if (updateHash) {
      this.replaceHash(sectionId);
    }

    window.setTimeout(() => {
      this.scrollSection(section, { alignTop, behavior: "auto" });

      const element = section.querySelector(selector);
      if (!(element instanceof HTMLElement)) {
        return;
      }

      callback(element);
    }, delay);

    if (alignTop) {
      window.setTimeout(() => {
        this.scrollSection(section, { alignTop, behavior: "auto" });
      }, delay + SECTION_SCROLL_SETTLE_DELAY_MS);
    }
  }

  ensureExpanded(section) {
    const panel = section.querySelector(".collapse");
    if (!(panel instanceof HTMLElement) || panel.classList.contains("show")) {
      return 0;
    }

    const toggle = section.querySelector(`[data-bs-target="#${panel.id}"]`) ||
      document.querySelector(`[data-bs-target="#${panel.id}"]`);

    if (toggle instanceof HTMLElement) {
      toggle.click();
      return SECTION_OPEN_DELAY_MS;
    }

    const CollapseClass = window.bootstrap?.Collapse;
    if (CollapseClass) {
      CollapseClass.getOrCreateInstance(panel, { toggle: false }).show();
      return SECTION_OPEN_DELAY_MS;
    }

    panel.classList.add("show");
    return 0;
  }

  clickElement(element) {
    if (!(element instanceof HTMLElement)) {
      return;
    }

    element.click();
  }

  contactButtonSelector() {
    if (this.hasContactButtonIdValue && this.contactButtonIdValue) {
      const escapedId = typeof CSS !== "undefined" && typeof CSS.escape === "function"
        ? CSS.escape(this.contactButtonIdValue)
        : this.contactButtonIdValue.replace(/([ #;?%&,.+*~':"!^$[\]()=>|/\\@])/g, "\\$1");
      return `#${escapedId}`;
    }

    return "[data-contact-cards-action='open-new']";
  }

  replaceHash(sectionId) {
    if (!sectionId) {
      return;
    }

    const nextHash = `#${sectionId}`;
    if (window.location.hash === nextHash) {
      return;
    }

    if (window.history?.replaceState) {
      window.history.replaceState(null, "", `${window.location.pathname}${window.location.search}${nextHash}`);
      return;
    }

    window.location.hash = sectionId;
  }

  scrollSection(section, { alignTop = false, behavior = "smooth" } = {}) {
    if (!(section instanceof HTMLElement)) {
      return;
    }

    const targetTop = alignTop ? this.sectionTopOffset(section) : this.sectionCenterOffset(section);
    this.ensureScrollCapacity(targetTop);
    const scrollRoot = document.scrollingElement || document.documentElement;

    window.scrollTo({ top: targetTop, behavior });

    if (typeof scrollRoot.scrollTo === "function") {
      scrollRoot.scrollTo({ top: targetTop, behavior });
    }

    scrollRoot.scrollTop = targetTop;
  }

  sectionTopOffset(section) {
    const scrollMarginTop = this.pxValue(window.getComputedStyle(section).scrollMarginTop);
    const sectionTop = window.scrollY + section.getBoundingClientRect().top;
    return Math.max(0, sectionTop - scrollMarginTop);
  }

  sectionCenterOffset(section) {
    const sectionRect = section.getBoundingClientRect();
    const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
    const currentTop = window.scrollY + sectionRect.top;
    const centeredTop = currentTop - Math.max(0, (viewportHeight - sectionRect.height) / 2);
    return Math.max(0, centeredTop);
  }

  pxValue(value) {
    const parsed = Number.parseFloat(value || "0");
    return Number.isFinite(parsed) ? parsed : 0;
  }

  ensureScrollCapacity(targetTop) {
    const scrollRoot = document.scrollingElement || document.documentElement;
    const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
    const maxScrollTop = Math.max(0, scrollRoot.scrollHeight - viewportHeight);
    const requiredExtra = Math.max(0, targetTop - maxScrollTop);

    if (requiredExtra <= 0) {
      this.clearScrollSpacer();
      return;
    }

    const spacer = this.scrollSpacer();
    spacer.style.height = `${Math.ceil(requiredExtra)}px`;
  }

  scrollSpacer() {
    if (!this._scrollSpacer || !this._scrollSpacer.isConnected) {
      const spacer = document.createElement("div");
      spacer.dataset.notepadQuickActionsScrollSpacer = "true";
      spacer.setAttribute("aria-hidden", "true");
      spacer.style.width = "1px";
      spacer.style.height = "0";
      spacer.style.pointerEvents = "none";
      spacer.style.opacity = "0";

      const contentElement = document.getElementById("content") || document.body;
      contentElement.appendChild(spacer);
      this._scrollSpacer = spacer;
    }

    return this._scrollSpacer;
  }

  clearScrollSpacer() {
    if (!this._scrollSpacer) {
      return;
    }

    this._scrollSpacer.remove();
    this._scrollSpacer = null;
  }

  locationInputSelector() {
    if (this.hasLocationInputIdValue && this.locationInputIdValue) {
      return `[id='${this.locationInputIdValue.replaceAll("'", "\\'")}']`;
    }

    return ".location-picker__search";
  }

  openCameraInput() {
    const input = this.cameraInput();
    if (!(input instanceof HTMLInputElement)) {
      const button = this.cameraButton();
      this.clickElement(button);
      return;
    }

    input.value = "";

    if (typeof input.showPicker === "function") {
      try {
        input.showPicker();
        return;
      } catch (_error) {
        // Fall back to click for browsers that block showPicker here.
      }
    }

    input.click();
  }

  cameraInput() {
    if (this.hasCameraInputIdValue) {
      const directInput = document.getElementById(this.cameraInputIdValue);
      if (directInput instanceof HTMLInputElement) {
        return directInput;
      }
    }

    const sectionRoot = this.photoCaptureRoot();
    if (sectionRoot) {
      const sectionInput = sectionRoot.querySelector("[data-photo-capture-target='cameraInput']");
      if (sectionInput instanceof HTMLInputElement) {
        return sectionInput;
      }
    }

    const siblingRoot = this.element.previousElementSibling;
    if (siblingRoot instanceof HTMLElement) {
      const siblingInput = siblingRoot.matches("[data-controller~='photo-capture']")
        ? siblingRoot.querySelector("[data-photo-capture-target='cameraInput']")
        : siblingRoot.querySelector("[data-controller~='photo-capture'] [data-photo-capture-target='cameraInput']");
      if (siblingInput instanceof HTMLInputElement) {
        return siblingInput;
      }
    }

    const fallbackInput = document.querySelector(".entry-photos-form-row[data-controller~='photo-capture'] [data-photo-capture-target='cameraInput']");
    return fallbackInput instanceof HTMLInputElement ? fallbackInput : null;
  }

  cameraButton() {
    if (this.hasCameraButtonIdValue) {
      const directButton = document.getElementById(this.cameraButtonIdValue);
      if (directButton instanceof HTMLElement) {
        return directButton;
      }
    }

    const sectionRoot = this.photoCaptureRoot();
    if (sectionRoot) {
      const sectionButton = sectionRoot.querySelector(".photo-section-camera-button, [data-photo-capture-target='cameraToggle']");
      if (sectionButton instanceof HTMLElement) {
        return sectionButton;
      }
    }

    const siblingRoot = this.element.previousElementSibling;
    if (siblingRoot instanceof HTMLElement) {
      const siblingButton = siblingRoot.matches("[data-controller~='photo-capture']")
        ? siblingRoot.querySelector(".photo-section-camera-button, [data-photo-capture-target='cameraToggle']")
        : siblingRoot.querySelector("[data-controller~='photo-capture'] .photo-section-camera-button, [data-controller~='photo-capture'] [data-photo-capture-target='cameraToggle']");
      if (siblingButton instanceof HTMLElement) {
        return siblingButton;
      }
    }

    return document.querySelector(".entry-photos-form-row[data-controller~='photo-capture'] .photo-section-camera-button, .entry-photos-form-row[data-controller~='photo-capture'] [data-photo-capture-target='cameraToggle']");
  }

  photoCaptureRoot() {
    if (!this.hasPhotosSectionIdValue) {
      return null;
    }

    const section = document.getElementById(this.photosSectionIdValue);
    if (!(section instanceof HTMLElement)) {
      return null;
    }

    if (section.matches("[data-controller~='photo-capture']")) {
      return section;
    }

    const nestedRoot = section.querySelector("[data-controller~='photo-capture']");
    return nestedRoot instanceof HTMLElement ? nestedRoot : section;
  }

  sync() {
    this.element.classList.toggle("is-open", this.isOpen);

    if (this.hasToggleTarget) {
      this.toggleTarget.setAttribute("aria-expanded", this.isOpen ? "true" : "false");
      this.toggleTarget.setAttribute("aria-pressed", this.isOpen ? "true" : "false");
    }

    if (this.hasMenuTarget) {
      this.menuTarget.setAttribute("aria-hidden", this.isOpen ? "false" : "true");
    }

    this.itemTargets.forEach((item) => {
      item.tabIndex = this.isOpen ? 0 : -1;
    });
  }
}
