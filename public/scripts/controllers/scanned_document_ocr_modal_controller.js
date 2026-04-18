import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = ["modal", "frame", "template"];

  connect() {
    this.boundReset = this.reset.bind(this);
    this.boundClick = this.handleClick.bind(this);

    if (this.hasModalTarget) {
      this.modalTarget.addEventListener("hidden.bs.modal", this.boundReset);
      this.modalTarget.addEventListener("click", this.boundClick);
    }
  }

  disconnect() {
    if (this.hasModalTarget) {
      this.modalTarget.removeEventListener("hidden.bs.modal", this.boundReset);
      this.modalTarget.removeEventListener("click", this.boundClick);
    }
  }

  openLink(event) {
    event.preventDefault();

    const url = event.currentTarget?.href;
    if (!url) {
      return;
    }

    this.load(url);
  }

  submitForm(event) {
    event.preventDefault();

    const form = event.currentTarget;
    if (!(form instanceof HTMLFormElement)) {
      return;
    }

    const method = (form.getAttribute("method") || "post").toUpperCase();
    const headers = this.requestHeaders();

    this.load(form.action, {
      method,
      headers,
      body: new FormData(form)
    });
  }

  handleClick(event) {
    const dismissTrigger = event.target.closest("[data-bs-dismiss='modal']");
    if (dismissTrigger) {
      event.preventDefault();
      this.hideModal();
      return;
    }

    if (event.target === this.modalTarget) {
      this.hideModal();
    }
  }

  async load(url, options = {}) {
    if (!this.hasFrameTarget) {
      return;
    }

    this.frameTarget.innerHTML = this.templateMarkup();
    this.showModal();

    const response = await fetch(url, {
      credentials: "same-origin",
      headers: this.requestHeaders(options.headers),
      ...options
    });

    if (!response.ok) {
      throw new Error(`Failed to load OCR modal content: ${response.status}`);
    }

    const html = await response.text();
    this.replaceFrameContent(html);
    this.showModal();
  }

  requestHeaders(extraHeaders = {}) {
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");

    return {
      Accept: "text/html",
      "X-Requested-With": "XMLHttpRequest",
      ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {}),
      ...extraHeaders
    };
  }

  replaceFrameContent(html) {
    if (!this.hasFrameTarget) {
      return;
    }

    const parser = new DOMParser();
    const documentFragment = parser.parseFromString(html, "text/html");
    const responseFrame = documentFragment.getElementById(this.frameTarget.id);

    this.frameTarget.innerHTML = responseFrame ? responseFrame.innerHTML : html;
  }

  showModal() {
    if (!this.hasModalTarget) {
      return;
    }

    const ModalClass = window.bootstrap?.Modal;
    if (ModalClass) {
      const modal = ModalClass.getInstance(this.modalTarget) || ModalClass.getOrCreateInstance(this.modalTarget);
      modal.show();
      return;
    }

    this.showFallback();
  }

  hideModal() {
    if (!this.hasModalTarget) {
      return;
    }

    const ModalClass = window.bootstrap?.Modal;
    const modal = ModalClass ? ModalClass.getInstance(this.modalTarget) : null;

    if (modal) {
      modal.hide();
      return;
    }

    this.hideFallback();
  }

  reset() {
    if (!this.hasFrameTarget) {
      return;
    }

    this.frameTarget.innerHTML = this.templateMarkup();
  }

  templateMarkup() {
    return this.hasTemplateTarget ? this.templateTarget.innerHTML.trim() : "";
  }

  showFallback() {
    this.modalTarget.style.display = "block";
    this.modalTarget.removeAttribute("aria-hidden");
    this.modalTarget.setAttribute("aria-modal", "true");
    this.modalTarget.setAttribute("role", "dialog");
    this.modalTarget.classList.add("show");
    document.body.classList.add("modal-open");
    this.ensureBackdrop();
  }

  hideFallback() {
    this.modalTarget.classList.remove("show");
    this.modalTarget.style.display = "none";
    this.modalTarget.setAttribute("aria-hidden", "true");
    this.modalTarget.removeAttribute("aria-modal");
    this.removeBackdrop();

    if (!document.querySelector(".modal.show")) {
      document.body.classList.remove("modal-open");
    }

    this.reset();
  }

  ensureBackdrop() {
    if (this.backdropElement?.isConnected) {
      return;
    }

    const backdrop = document.createElement("div");
    backdrop.className = "modal-backdrop fade show";
    document.body.appendChild(backdrop);
    this.backdropElement = backdrop;
  }

  removeBackdrop() {
    if (!this.backdropElement) {
      return;
    }

    this.backdropElement.remove();
    this.backdropElement = null;
  }
}
