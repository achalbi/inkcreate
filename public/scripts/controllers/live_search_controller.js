import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = ["actions", "field", "form", "results", "scope"];

  static values = {
    delay: { type: Number, default: 220 }
  };

  connect() {
    this.timeoutId = null;
    this.isComposing = false;
    this.requestAbortController = null;
  }

  disconnect() {
    this.clearPendingSubmit();
    this.abortInFlightRequest();
  }

  queueSubmit() {
    if (this.isComposing) {
      return;
    }

    this.clearPendingSubmit();
    this.timeoutId = window.setTimeout(() => this.submit(), this.delayValue);
  }

  pause() {
    this.isComposing = true;
    this.clearPendingSubmit();
  }

  resume() {
    this.isComposing = false;
    this.queueSubmit();
  }

  submitNow(event) {
    event?.preventDefault();
    this.submit();
  }

  async submit() {
    this.clearPendingSubmit();

    if (!this.hasFormTarget || !this.hasFieldTarget || !this.hasResultsTarget) {
      this.submitWithPageNavigation();
      return;
    }

    const url = this.buildUrl();
    const selectionStart = this.fieldTarget.selectionStart;
    const selectionEnd = this.fieldTarget.selectionEnd;

    this.abortInFlightRequest();
    this.requestAbortController = new AbortController();

    try {
      const response = await fetch(url.toString(), {
        headers: {
          "X-Requested-With": "XMLHttpRequest"
        },
        signal: this.requestAbortController.signal
      });

      if (!response.ok) {
        throw new Error(`Search request failed with status ${response.status}`);
      }

      const html = await response.text();
      const documentFragment = new DOMParser().parseFromString(html, "text/html");

      this.replaceTargetContent("scope", documentFragment);
      this.replaceTargetContent("actions", documentFragment);
      this.replaceTargetContent("results", documentFragment);

      window.history.replaceState({}, "", url);

      this.fieldTarget.focus({ preventScroll: true });

      if (selectionStart !== null && selectionEnd !== null) {
        this.fieldTarget.setSelectionRange(selectionStart, selectionEnd);
      }
    } catch (error) {
      if (error.name === "AbortError") {
        return;
      }

      this.submitWithPageNavigation(url);
    } finally {
      this.requestAbortController = null;
    }
  }

  buildUrl() {
    const url = new URL(this.formTarget.action || window.location.href, window.location.origin);
    const formData = new FormData(this.formTarget);

    url.search = "";

    formData.forEach((value, key) => {
      const normalizedValue = typeof value === "string" ? value.trim() : value;

      if (normalizedValue) {
        url.searchParams.set(key, normalizedValue);
      }
    });

    return url;
  }

  replaceTargetContent(targetName, nextDocument) {
    const currentTarget = this[`${targetName}Target`];

    if (!currentTarget) {
      return;
    }

    const selector = `[data-live-search-target="${targetName}"]`;
    const nextTarget = nextDocument.querySelector(selector);

    if (!nextTarget) {
      return;
    }

    currentTarget.innerHTML = nextTarget.innerHTML;
  }

  submitWithPageNavigation(url = this.buildUrl()) {
    window.location.assign(url.toString());
  }

  clearPendingSubmit() {
    if (this.timeoutId === null) {
      return;
    }

    window.clearTimeout(this.timeoutId);
    this.timeoutId = null;
  }

  abortInFlightRequest() {
    if (!this.requestAbortController) {
      return;
    }

    this.requestAbortController.abort();
    this.requestAbortController = null;
  }
}
