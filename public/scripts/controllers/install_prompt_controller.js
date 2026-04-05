import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  connect() {
    this.deferredPrompt = null;
    window.addEventListener("beforeinstallprompt", (event) => {
      event.preventDefault();
      this.deferredPrompt = event;
    });
  }

  async prompt() {
    if (this.deferredPrompt) {
      this.deferredPrompt.prompt();
      await this.deferredPrompt.userChoice;
      this.deferredPrompt = null;
      return;
    }

    window.alert("Use your browser menu to install Inkcreate. On iPhone Safari, tap Share and then Add to Home Screen.");
  }
}
