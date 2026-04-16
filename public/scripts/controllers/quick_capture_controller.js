import { Controller } from "/scripts/vendor/stimulus.js";
import { currentCaptureQualityPreset, optimizeImageFiles } from "/scripts/capture_quality.js";

export default class extends Controller {
  static targets = ["form", "cameraInput", "galleryInput", "cameraButton", "galleryButton", "status"];

  connect() {
    this.submitting = false;
  }

  openCamera(event) {
    event?.preventDefault();
    this.openInput(this.cameraInputTarget);
  }

  openGallery(event) {
    event?.preventDefault();
    this.openInput(this.galleryInputTarget);
  }

  async submitFromSelection(event) {
    const input = event.currentTarget;
    const files = Array.from(input.files || []);

    if (this.submitting || files.length === 0) {
      return;
    }

    this.submitting = true;
    this.setButtonsDisabled(true);
    this.showStatus(
      currentCaptureQualityPreset() === "original"
        ? "Creating your daily page and opening edit mode..."
        : "Optimizing your image and creating the daily page..."
    );

    const optimizedFiles = await optimizeImageFiles(files);
    this.replaceInputFiles(input, optimizedFiles);

    window.InkcreatePageLoader?.show("Creating your daily page...");

    if (typeof this.formTarget.requestSubmit === "function") {
      this.formTarget.requestSubmit();
    } else {
      this.formTarget.submit();
    }
  }

  openInput(input) {
    if (this.submitting || !input) {
      return;
    }

    input.value = "";

    if (typeof input.showPicker === "function") {
      try {
        input.showPicker();
        return;
      } catch (_error) {
        // Fall back to click when showPicker is blocked.
      }
    }

    input.click();
  }

  setButtonsDisabled(disabled) {
    if (this.hasCameraButtonTarget) {
      this.cameraButtonTarget.disabled = disabled;
    }

    if (this.hasGalleryButtonTarget) {
      this.galleryButtonTarget.disabled = disabled;
    }
  }

  showStatus(message) {
    if (!this.hasStatusTarget) {
      return;
    }

    this.statusTarget.hidden = false;
    this.statusTarget.textContent = message;
  }

  replaceInputFiles(input, files) {
    const dataTransfer = new DataTransfer();
    files.forEach((file) => dataTransfer.items.add(file));
    input.files = dataTransfer.files;
  }
}
