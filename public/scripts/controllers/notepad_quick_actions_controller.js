import { Controller } from "/scripts/vendor/stimulus.js";

const SECTION_OPEN_DELAY_MS = 220;

export default class extends Controller {
  static targets = ["menu", "toggle", "item"];

  static values = {
    cameraInputId: String,
    cameraButtonId: String,
    voiceSectionId: String,
    todoSectionId: String,
    scanSectionId: String
  };

  connect() {
    this.isOpen = false;
    this.sync();
  }

  disconnect() {
    this.isOpen = false;
    this.sync();
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

  openScan(event) {
    event?.preventDefault();
    this.close();

    this.runSectionAction(this.scanSectionIdValue, {
      selector: "[data-action*='document-capture#open']",
      callback: (button) => button.click()
    });
  }

  runSectionAction(sectionId, { selector, callback }) {
    if (!sectionId) {
      return;
    }

    const section = document.getElementById(sectionId);
    if (!(section instanceof HTMLElement)) {
      return;
    }

    const delay = this.ensureExpanded(section);
    section.scrollIntoView({ behavior: "smooth", block: "center", inline: "nearest" });

    window.setTimeout(() => {
      const element = section.querySelector(selector);
      if (!(element instanceof HTMLElement)) {
        return;
      }

      callback(element);
    }, delay);
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

    const siblingRoot = this.element.previousElementSibling;
    if (siblingRoot instanceof HTMLElement && siblingRoot.matches("[data-controller~='photo-capture']")) {
      const siblingInput = siblingRoot.querySelector("[data-photo-capture-target='cameraInput']");
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

    const siblingRoot = this.element.previousElementSibling;
    if (siblingRoot instanceof HTMLElement && siblingRoot.matches("[data-controller~='photo-capture']")) {
      return siblingRoot.querySelector(".photo-section-camera-button, [data-photo-capture-target='cameraToggle']");
    }

    return document.querySelector(".entry-photos-form-row[data-controller~='photo-capture'] .photo-section-camera-button, .entry-photos-form-row[data-controller~='photo-capture'] [data-photo-capture-target='cameraToggle']");
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
