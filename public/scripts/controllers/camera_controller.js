import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = ["preview"];

  async start() {
    if (!navigator.mediaDevices?.getUserMedia) {
      window.alert("Camera capture is not available in this browser. Use gallery upload instead.");
      return;
    }

    this.stop();

    this.stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: { ideal: "environment" } },
      audio: false
    });

    this.video = document.createElement("video");
    this.video.autoplay = true;
    this.video.playsInline = true;
    this.video.srcObject = this.stream;
    this.previewTarget.innerHTML = "";
    this.previewTarget.appendChild(this.video);
  }

  async capture() {
    if (!this.video) {
      window.alert("Start the camera before capturing.");
      return;
    }

    const canvas = document.createElement("canvas");
    canvas.width = this.video.videoWidth || 1280;
    canvas.height = this.video.videoHeight || 960;
    const context = canvas.getContext("2d");
    context.drawImage(this.video, 0, 0, canvas.width, canvas.height);

    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.92));
    const file = new File([blob], `capture-${Date.now()}.jpg`, { type: "image/jpeg" });

    this.element.dispatchEvent(new CustomEvent("inkcreate:file-selected", {
      bubbles: true,
      detail: { file, previewDataUrl: canvas.toDataURL("image/jpeg", 0.7) }
    }));

    this.previewTarget.innerHTML = "";
    const image = document.createElement("img");
    image.src = canvas.toDataURL("image/jpeg", 0.7);
    image.alt = "Captured notebook preview";
    this.previewTarget.appendChild(image);
    this.stop();
  }

  disconnect() {
    this.stop();
  }

  stop() {
    if (!this.stream) {
      return;
    }

    this.stream.getTracks().forEach((track) => track.stop());
    this.stream = null;
    this.video = null;
  }
}
