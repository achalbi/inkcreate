import { Controller } from "/scripts/vendor/stimulus.js";

const GEOLOCATION_TIMEOUT_MS = 12000;

export default class extends Controller {
  static targets = ["form", "latitude", "longitude", "button", "status"];

  stamp(event) {
    event?.preventDefault?.();

    if (!("geolocation" in navigator)) {
      this.reportError("Location isn't available on this device.");
      return;
    }

    this.setBusy(true);
    this.updateStatus("Locating your position…");

    navigator.geolocation.getCurrentPosition(
      (position) => this.onPosition(position),
      (error) => this.onError(error),
      { enableHighAccuracy: true, timeout: GEOLOCATION_TIMEOUT_MS, maximumAge: 0 }
    );
  }

  onPosition(position) {
    const { latitude, longitude } = position.coords || {};
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
      this.reportError("Couldn't read your coordinates.");
      return;
    }

    if (this.hasLatitudeTarget) {
      this.latitudeTarget.value = String(latitude);
    }
    if (this.hasLongitudeTarget) {
      this.longitudeTarget.value = String(longitude);
    }

    this.updateStatus("Saving location…");
    if (this.hasFormTarget) {
      this.formTarget.requestSubmit?.() || this.formTarget.submit();
    }
  }

  onError(error) {
    const message = error?.code === 1
      ? "Location permission denied."
      : "Couldn't get your location.";
    this.reportError(message);
  }

  reportError(message) {
    this.setBusy(false);
    this.updateStatus(message);
  }

  setBusy(isBusy) {
    if (!this.hasButtonTarget) {
      return;
    }
    this.buttonTarget.disabled = isBusy;
    this.buttonTarget.setAttribute("aria-busy", isBusy ? "true" : "false");
  }

  updateStatus(text) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = text;
    }
  }
}
