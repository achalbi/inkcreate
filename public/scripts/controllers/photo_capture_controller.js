import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = ["input", "cameraFrame", "previewGrid", "emptyState", "count"];

  connect() {
    this.stream = null;
    this.video = null;
    this.pendingFiles = Array.from(this.inputTarget.files || []);
    this.renderPendingPreviews();
  }

  disconnect() {
    this.stop();
  }

  placeholderMarkup() {
    return `
      <div class="small text-muted" style="max-width: 260px;">
        <strong>Live camera preview</strong>
        <p class="mb-0">Use the rear camera, keep the A5 page inside the frame, and capture when the notes look sharp.</p>
      </div>
    `;
  }

  async start() {
    if (!navigator.mediaDevices?.getUserMedia) {
      window.alert("Live camera preview is not available in this browser. Use the phone camera upload button instead.");
      return;
    }

    try {
      this.stop();

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
    } catch (_error) {
      window.alert("Camera access was blocked. You can still upload from the phone camera or gallery below.");
    }
  }

  async capture() {
    if (!this.video) {
      window.alert("Start the camera preview before capturing.");
      return;
    }

    const canvas = document.createElement("canvas");
    canvas.width = this.video.videoWidth || 1600;
    canvas.height = this.video.videoHeight || 1200;

    const context = canvas.getContext("2d");
    context.drawImage(this.video, 0, 0, canvas.width, canvas.height);

    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.92));
    if (!blob) {
      window.alert("The browser could not create the image. Try again.");
      return;
    }

    const file = new File([blob], `a5-notes-${Date.now()}.jpg`, { type: "image/jpeg" });
    this.addFiles([file]);
  }

  stop() {
    if (this.stream) {
      this.stream.getTracks().forEach((track) => track.stop());
    }

    this.stream = null;
    this.video = null;

    if (this.hasCameraFrameTarget) {
      this.cameraFrameTarget.innerHTML = this.placeholderMarkup();
    }
  }

  syncFromInput() {
    this.pendingFiles = Array.from(this.inputTarget.files || []);
    this.renderPendingPreviews();
  }

  addFiles(files) {
    this.pendingFiles = [...this.pendingFiles, ...files];

    const dataTransfer = new DataTransfer();
    this.pendingFiles.forEach((file) => dataTransfer.items.add(file));
    this.inputTarget.files = dataTransfer.files;

    this.renderPendingPreviews();
  }

  renderPendingPreviews() {
    if (!this.hasPreviewGridTarget || !this.hasEmptyStateTarget || !this.hasCountTarget) {
      return;
    }

    this.previewGridTarget.innerHTML = "";
    this.countTarget.textContent = `${this.pendingFiles.length}`;

    if (this.pendingFiles.length === 0) {
      this.emptyStateTarget.style.display = "";
      return;
    }

    this.emptyStateTarget.style.display = "none";

    this.pendingFiles.forEach((file) => {
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
        preview.innerHTML = `<div class="small text-muted" style="padding: 24px 12px; text-align: center;"><strong>${file.name}</strong></div>`;
      }

      const body = document.createElement("div");
      body.className = "caption";
      body.innerHTML = `
        <div style="font-weight: 600; word-break: break-word;">${file.name}</div>
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
}
