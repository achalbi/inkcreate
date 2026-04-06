import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static values = {
    returnTo: String
  };

  connect() {
    this.handleMessage = this.handleMessage.bind(this);
    window.addEventListener("message", this.handleMessage);
  }

  disconnect() {
    window.removeEventListener("message", this.handleMessage);
  }

  open(event) {
    if (this.element.dataset.driveOauthSubmitting === "true") {
      delete this.element.dataset.driveOauthSubmitting;
      return;
    }

    event.preventDefault();

    const popup = window.open("", "inkcreateDriveOauth", this.popupFeatures());
    if (!popup) {
      this.element.dataset.driveOauthSubmitting = "true";

      if (typeof this.element.requestSubmit === "function") {
        this.element.requestSubmit();
      } else {
        this.element.submit();
      }

      return;
    }

    popup.focus();

    const previousTarget = this.element.getAttribute("target");
    this.element.setAttribute("target", "inkcreateDriveOauth");
    this.element.submit();

    if (previousTarget) {
      this.element.setAttribute("target", previousTarget);
    } else {
      this.element.removeAttribute("target");
    }
  }

  handleMessage(event) {
    if (event.origin !== window.location.origin) return;
    if (!event.data || event.data.type !== "inkcreate:drive-oauth") return;

    window.location.assign(event.data.returnTo || this.returnToValue || window.location.href);
  }

  popupFeatures() {
    const width = 520;
    const height = 720;
    const left = Math.max(0, Math.round((window.screen.width - width) / 2));
    const top = Math.max(0, Math.round((window.screen.height - height) / 2));

    return `popup=yes,width=${width},height=${height},left=${left},top=${top},resizable=yes,scrollbars=yes`;
  }
}
