import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = ["input", "cameraFrame", "cameraPanel", "defaultActions", "previewActions", "previewGrid", "retainedGrid", "retainedInput", "retainedItem", "emptyState", "cameraToggle", "errorModal", "errorTitle", "errorMessage"];

  connect() {
    this.stream = null;
    this.video = null;
    this.errorModalInstance = null;
    this.pendingFiles = Array.from(this.inputTarget.files || []);
    this.resetPreviewState();
    this.renderPendingPreviews();
  }

  disconnect() {
    this.stop();
    this.disposeErrorModal();
  }

  showError({ title, message }) {
    if (this.hasErrorTitleTarget) {
      this.errorTitleTarget.textContent = title;
    }

    if (this.hasErrorMessageTarget) {
      this.errorMessageTarget.textContent = message;
    }

    const ModalClass = window.bootstrap?.Modal;
    if (ModalClass && this.hasErrorModalTarget) {
      this.errorModalInstance = ModalClass.getOrCreateInstance(this.errorModalTarget);
      this.errorModalInstance.show();
      return;
    }

    window.alert(message);
  }

  disposeErrorModal() {
    if (!this.errorModalInstance) return;

    this.errorModalInstance.dispose();
    this.errorModalInstance = null;
  }

  resetPreviewState() {
    if (this.hasCameraPanelTarget) {
      this.cameraPanelTarget.hidden = true;
    }

    if (this.hasDefaultActionsTarget) {
      this.defaultActionsTarget.hidden = false;
    }

    if (this.hasPreviewActionsTarget) {
      this.previewActionsTarget.hidden = true;
    }

    this.toggleCameraButton(false);
  }

  showPreviewState() {
    if (this.hasCameraPanelTarget) {
      this.cameraPanelTarget.hidden = false;
    }

    if (this.hasDefaultActionsTarget) {
      this.defaultActionsTarget.hidden = true;
    }

    if (this.hasPreviewActionsTarget) {
      this.previewActionsTarget.hidden = false;
    }

    this.toggleCameraButton(true);
  }

  toggleCameraButton(active) {
    if (!this.hasCameraToggleTarget) return;

    this.cameraToggleTargets.forEach((button) => {
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", active ? "true" : "false");
    });
  }

  async start(event) {
    event?.preventDefault();

    if (this.stream && this.video) {
      this.showPreviewState();
      return;
    }

    if (!navigator.mediaDevices?.getUserMedia) {
      this.showError({
        title: "Live preview unavailable",
        message: "This browser does not support live camera preview here. You can still upload from the gallery."
      });
      return;
    }

    try {
      this.stopStream();

      this.stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: { ideal: "environment" },
          width: { ideal: 1920 },
          height: { ideal: 1080 }
        },
        audio: false
      });

      this.video = document.createElement("video");
      this.video.autoplay = true;
      this.video.playsInline = true;
      this.video.muted = true;
      this.video.srcObject = this.stream;
      this.video.style.width = "100%";
      this.video.style.maxHeight = "320px";
      this.video.style.objectFit = "cover";
      this.video.style.borderRadius = "4px";

      this.cameraFrameTarget.innerHTML = "";
      this.cameraFrameTarget.appendChild(this.video);
      this.showPreviewState();
    } catch (error) {
      this.resetPreviewState();
      const message = error?.name === "NotAllowedError"
        ? "Camera access was blocked. Allow camera permission and try again, or use Upload from gallery instead."
        : "The camera could not be opened right now. You can still use Upload from gallery instead.";

      this.showError({
        title: "Camera access blocked",
        message
      });
    }
  }

  async capture() {
    if (!this.video) {
      this.showError({
        title: "Preview not started",
        message: "Open live preview before capturing a photo."
      });
      return;
    }

    const canvas = document.createElement("canvas");
    canvas.width = this.video.videoWidth || 1600;
    canvas.height = this.video.videoHeight || 1200;

    const context = canvas.getContext("2d");
    context.drawImage(this.video, 0, 0, canvas.width, canvas.height);

    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.92));
    if (!blob) {
      this.showError({
        title: "Capture failed",
        message: "The browser could not create the image. Try again."
      });
      return;
    }

    const file = new File([blob], `note-capture-${Date.now()}.jpg`, { type: "image/jpeg" });
    this.addFiles([file]);
  }

  cancel(event) {
    event?.preventDefault();
    this.stop();
  }

  stop() {
    this.stopStream();
    this.resetPreviewState();
  }

  stopStream() {
    if (this.stream) {
      this.stream.getTracks().forEach((track) => track.stop());
    }

    this.stream = null;
    this.video = null;

    if (this.hasCameraFrameTarget) {
      this.cameraFrameTarget.innerHTML = "";
    }
  }

  syncFromInput() {
    this.pendingFiles = Array.from(this.inputTarget.files || []);
    this.renderPendingPreviews();
  }

  chooseFromGallery(event) {
    event?.preventDefault();

    if (!this.hasInputTarget) return;

    this.inputTarget.click();
  }

  addFiles(files) {
    this.pendingFiles = [...this.pendingFiles, ...files];

    this.syncInputFiles();

    this.renderPendingPreviews();
  }

  removePendingUpload(event) {
    event?.preventDefault();

    const index = Number.parseInt(event.currentTarget.dataset.pendingIndex || "", 10);
    if (!Number.isInteger(index) || index < 0 || index >= this.pendingFiles.length) {
      return;
    }

    this.pendingFiles = this.pendingFiles.filter((_, fileIndex) => fileIndex !== index);
    this.syncInputFiles();
    this.renderPendingPreviews();
  }

  removeRetainedUpload(event) {
    event?.preventDefault();

    const signedId = event.currentTarget.dataset.signedId;
    if (!signedId) return;

    this.retainedInputTargets
      .filter((input) => input.value === signedId)
      .forEach((input) => input.remove());

    this.retainedItemTargets
      .filter((item) => item.dataset.signedId === signedId)
      .forEach((item) => item.remove());

    this.renderPendingPreviews();
  }

  renderPendingPreviews() {
    if (!this.hasPreviewGridTarget || !this.hasEmptyStateTarget) {
      return;
    }

    this.previewGridTarget.innerHTML = "";
    const hasRetainedUploads = this.hasRetainedGridTarget && this.retainedGridTarget.children.length > 0;

    if (this.pendingFiles.length === 0) {
      this.emptyStateTarget.style.display = hasRetainedUploads ? "none" : "";
      return;
    }

    this.emptyStateTarget.style.display = "none";

    this.pendingFiles.forEach((file, index) => {
      const item = document.createElement("div");
      item.className = "col-sm-6 col-md-4";

      const card = document.createElement("div");
      card.className = "thumbnail";
      card.style.marginBottom = "15px";

      const preview = document.createElement("div");
      preview.style.background = "#f8f8f8";

      if (file.type.startsWith("image/")) {
        const image = document.createElement("img");
        image.alt = file.name;
        image.className = "img-responsive";
        image.style.width = "100%";
        image.style.height = "180px";
        image.style.objectFit = "cover";
        image.src = URL.createObjectURL(file);
        preview.appendChild(image);
      } else {
        preview.innerHTML = `<div class="small text-muted" style="padding: 24px 12px; text-align: center;"><strong>${this.escapeHtml(file.name)}</strong></div>`;
      }

      const body = document.createElement("div");
      body.className = "caption";
      body.innerHTML = `
        <div class="photo-capture-card-heading">
          <div style="font-weight: 600; word-break: break-word;">${this.escapeHtml(file.name)}</div>
          <button
            type="button"
            class="btn btn-danger btn-xs photo-capture-remove-button"
            data-action="photo-capture#removePendingUpload"
            data-pending-index="${index}"
          >
            Remove
          </button>
        </div>
        <div class="text-muted small">${this.humanSize(file.size)}</div>
      `;

      card.appendChild(preview);
      card.appendChild(body);
      item.appendChild(card);
      this.previewGridTarget.appendChild(item);
    });
  }

  humanSize(bytes) {
    if (!bytes) return "0 KB";
    const size = bytes / 1024;
    if (size < 1024) return `${Math.round(size)} KB`;
    return `${(size / 1024).toFixed(1)} MB`;
  }

  syncInputFiles() {
    const dataTransfer = new DataTransfer();
    this.pendingFiles.forEach((file) => dataTransfer.items.add(file));
    this.inputTarget.files = dataTransfer.files;
  }

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll("\"", "&quot;")
      .replaceAll("'", "&#39;");
  }
}
