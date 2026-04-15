import { Controller } from "/scripts/vendor/stimulus.js";

const MIME_CANDIDATES = [
  "audio/webm;codecs=opus",
  "audio/mp4",
  "audio/webm",
  "audio/ogg;codecs=opus"
];

export default class extends Controller {
  static targets = [
    "startButton",
    "stopButton",
    "live",
    "timer",
    "panel",
    "preview",
    "previewAudio",
    "previewMeta",
    "saveButton",
    "discardButton",
    "feedback",
    "recordings",
    "fileInput",
    "metadata",
    "fallbackInput"
  ];

  static values = {
    autoSubmitOnSave: { type: Boolean, default: false },
    createUrl: String,
    maxDurationSeconds: { type: Number, default: 7200 },
    mode: { type: String, default: "persisted" },
    paramKey: { type: String, default: "page" }
  };

  connect() {
    this.isSaving = false;
    this.pendingRecording = null;
    this.pendingFormRecordings = [];
    this.recordingChunks = [];
    this.stream = null;
    this.mediaRecorder = null;
    this.recordingStartedAt = null;
    this.timerId = null;
    this.autoStopId = null;
    this.renderPendingRecordings();
    this.renderIdleState();
  }

  disconnect() {
    this.stopStream();
    this.clearTimers();
  }

  async start() {
    if (this.isSaving) {
      return;
    }

    this.expandPanel();

    if (!this.canRecordInBrowser()) {
      this.discard();
      this.openFallbackCapture();
      return;
    }

    this.discard();
    const permissionState = await this.microphonePermissionState();

    if (permissionState === "denied") {
      this.setFeedback("Microphone access is blocked. Enable microphone permission in your browser settings and try again.");
      return;
    }

    this.setFeedback("Checking microphone access...");

    try {
      if (permissionState === "prompt") {
        this.setFeedback("Allow microphone access to start recording.");
      }

      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      this.beginRecording(stream);
    } catch (error) {
      this.stopStream();
      this.setFeedback(this.microphoneAccessErrorMessage(error));
    }
  }

  async selectFallbackRecording(event) {
    if (this.isSaving) {
      event.target.value = "";
      return;
    }

    const file = event.target.files?.[0];
    event.target.value = "";

    if (!file) {
      return;
    }

    this.discard();

    const previewUrl = URL.createObjectURL(file);
    const durationSeconds = await this.audioDurationFor(previewUrl);

    this.pendingRecording = {
      durationSeconds,
      recordedAt: new Date().toISOString(),
      file,
      previewUrl
    };

    this.renderPreviewState();
    this.renderPreviewMetadata();
    this.setFeedback("Review the recording and save it when ready.");
  }

  stop() {
    if (!this.mediaRecorder || this.mediaRecorder.state === "inactive") {
      return;
    }

    this.mediaRecorder.stop();
    this.renderStoppingState();
  }

  discard() {
    this.pendingRecording = null;

    if (this.hasPreviewAudioTarget) {
      this.previewAudioTarget.removeAttribute("src");
      this.previewAudioTarget.load();
    }

    this.renderIdleState();
  }

  async save() {
    if (!this.pendingRecording || this.isSaving) {
      return;
    }

    this.isSaving = true;
    this.syncActionState();

    try {
      if (this.hasCreateUrlValue) {
        this.setFeedback("Saving voice note...");
        await this.uploadPendingRecording();
        return;
      }

      if (this.modeValue === "form") {
        this.pendingFormRecordings.push(this.pendingRecording);

        if (this.autoSubmitOnSaveValue) {
          this.syncPendingFormRecordings();
          this.setFeedback("Saving your voice note...");
          this.discard();
          this.submitClosestForm();
          return;
        }

        this.renderPendingRecordings();
        this.setFeedback("Voice note added to this form.");
        this.discard();
        return;
      }

      this.setFeedback("Saving voice note...");
      await this.uploadPendingRecording();
    } finally {
      this.isSaving = false;
      this.syncActionState();
    }
  }

  removePending(event) {
    const index = Number.parseInt(event.currentTarget.dataset.index || "", 10);
    if (!Number.isFinite(index)) {
      return;
    }

    this.pendingFormRecordings.splice(index, 1);
    this.renderPendingRecordings();
  }

  supportedMimeType() {
    const RecorderClass = this.mediaRecorderClass();
    if (typeof RecorderClass?.isTypeSupported !== "function") {
      return null;
    }

    return MIME_CANDIDATES.find((candidate) => RecorderClass.isTypeSupported(candidate)) || null;
  }

  async microphonePermissionState() {
    if (!navigator.permissions?.query) {
      return null;
    }

    try {
      const status = await navigator.permissions.query({ name: "microphone" });
      return status?.state || null;
    } catch (_error) {
      return null;
    }
  }

  beginRecording(stream) {
    this.stream = stream;
    this.recordingChunks = [];
    this.recordingStartedAt = new Date();

    const mimeType = this.supportedMimeType();
    const RecorderClass = this.mediaRecorderClass();
    this.mediaRecorder = mimeType ? new RecorderClass(this.stream, { mimeType }) : new RecorderClass(this.stream);
    this.mediaRecorder.addEventListener("dataavailable", (event) => {
      if (event.data?.size) {
        this.recordingChunks.push(event.data);
      }
    });
    this.mediaRecorder.addEventListener("stop", () => this.finalizeRecording());
    this.mediaRecorder.start();

    this.startTimer();
    this.autoStopId = window.setTimeout(() => this.stop(), this.maxDurationSecondsValue * 1000);
    this.renderRecordingState();
    this.setFeedback("Recording started.");
  }

  startTimer() {
    this.clearTimers();
    this.updateTimer();
    this.timerId = window.setInterval(() => this.updateTimer(), 1000);
  }

  updateTimer() {
    if (!this.hasTimerTarget) {
      return;
    }

    const elapsedSeconds = this.elapsedSeconds();
    const minutes = Math.floor(elapsedSeconds / 60);
    const seconds = elapsedSeconds % 60;
    this.timerTarget.textContent = `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
  }

  elapsedSeconds() {
    if (!this.recordingStartedAt) {
      return 0;
    }

    return Math.max(Math.round((Date.now() - this.recordingStartedAt.getTime()) / 1000), 0);
  }

  clearTimers() {
    window.clearInterval(this.timerId);
    window.clearTimeout(this.autoStopId);
    this.timerId = null;
    this.autoStopId = null;
  }

  async finalizeRecording() {
    const mimeType = this.mediaRecorder?.mimeType || this.supportedMimeType() || "audio/webm";
    const durationSeconds = this.elapsedSeconds();
    const recordedAt = this.recordingStartedAt || new Date();
    const blob = new Blob(this.recordingChunks, { type: mimeType });
    const extension = mimeType.includes("mp4") ? "m4a" : "webm";

    this.pendingRecording = {
      durationSeconds,
      recordedAt: recordedAt.toISOString(),
      file: new File([blob], `voice-note-${Date.now()}.${extension}`, { type: mimeType }),
      previewUrl: URL.createObjectURL(blob)
    };

    this.stopStream();
    this.clearTimers();
    this.renderPreviewState();
    this.renderPreviewMetadata();
    this.setFeedback("Review the recording and save it when ready.");
  }

  renderPreviewMetadata() {
    if (!this.pendingRecording || !this.hasPreviewAudioTarget || !this.hasPreviewMetaTarget) {
      return;
    }

    this.previewAudioTarget.src = this.pendingRecording.previewUrl;
    this.previewAudioTarget.load();

    const fileSize = this.formatBytes(this.pendingRecording.file.size);
    const duration = this.formatDuration(this.pendingRecording.durationSeconds);
    this.previewMetaTarget.textContent = `${duration} · ${fileSize}`;
  }

  renderPendingRecordings() {
    if (!this.hasRecordingsTarget) {
      return;
    }

    this.recordingsTarget.innerHTML = "";
    this.syncPendingFormRecordings();

    this.pendingFormRecordings.forEach((recording, index) => {
      const item = document.createElement("div");
      item.className = "voice-note-recorder__pending-item";
      item.innerHTML = `
        <div class="voice-note-recorder__pending-copy">
          <strong>${this.formatDuration(recording.durationSeconds)}</strong>
          <span>${this.formatBytes(recording.file.size)}</span>
        </div>
        <button type="button" class="btn btn-white btn-sm btn-icon" data-index="${index}" aria-label="Remove pending voice note">
          <i class="ti ti-x"></i>
        </button>
      `;

      const removeButton = item.querySelector("button");
      removeButton.addEventListener("click", (event) => this.removePending(event));
      this.recordingsTarget.appendChild(item);
    });
  }

  syncPendingFormRecordings() {
    if (this.hasMetadataTarget) {
      this.metadataTarget.innerHTML = "";
    }

    if (this.hasFileInputTarget) {
      const dataTransfer = new DataTransfer();

      this.pendingFormRecordings.forEach((recording) => {
        dataTransfer.items.add(recording.file);

        if (this.hasMetadataTarget) {
          const durationField = document.createElement("input");
          durationField.type = "hidden";
          durationField.name = `${this.paramKeyValue}[voice_note_duration_seconds][]`;
          durationField.value = String(recording.durationSeconds);
          this.metadataTarget.appendChild(durationField);

          const recordedAtField = document.createElement("input");
          recordedAtField.type = "hidden";
          recordedAtField.name = `${this.paramKeyValue}[voice_note_recorded_ats][]`;
          recordedAtField.value = recording.recordedAt;
          this.metadataTarget.appendChild(recordedAtField);
        }

      });

      this.fileInputTarget.files = dataTransfer.files;
    }
  }

  async uploadPendingRecording() {
    if (!this.hasCreateUrlValue || !this.pendingRecording) {
      return;
    }

    const formData = new FormData();
    formData.append("voice_note[audio]", this.pendingRecording.file);
    formData.append("voice_note[duration_seconds]", String(this.pendingRecording.durationSeconds));
    formData.append("voice_note[recorded_at]", this.pendingRecording.recordedAt);

    try {
      const response = await fetch(this.createUrlValue, {
        method: "POST",
        body: formData,
        credentials: "same-origin",
        headers: {
          "X-CSRF-Token": this.csrfToken(),
          "Accept": "application/json"
        }
      });

      const payload = await response.json();
      if (!response.ok || payload.ok === false) {
        throw new Error(payload.error || "Voice note could not be saved.");
      }

      this.discard();
      window.location.reload();
    } catch (error) {
      this.setFeedback(error.message || "Voice note could not be saved right now.");
    }
  }

  renderRecordingState() {
    if (this.hasStartButtonTarget) this.startButtonTarget.hidden = true;
    if (this.hasStopButtonTarget) this.stopButtonTarget.hidden = false;
    if (this.hasLiveTarget) this.liveTarget.hidden = false;
    if (this.hasPreviewTarget) this.previewTarget.hidden = true;
    this.syncActionState();
  }

  renderStoppingState() {
    if (this.hasStopButtonTarget) this.stopButtonTarget.disabled = true;
    this.setFeedback("Finalizing your recording...");
  }

  renderPreviewState() {
    this.expandPanel();
    if (this.hasStartButtonTarget) this.startButtonTarget.hidden = false;
    if (this.hasStopButtonTarget) {
      this.stopButtonTarget.hidden = true;
      this.stopButtonTarget.disabled = false;
    }
    if (this.hasLiveTarget) this.liveTarget.hidden = true;
    if (this.hasPreviewTarget) this.previewTarget.hidden = false;
    if (this.hasSaveButtonTarget) this.saveButtonTarget.hidden = false;
    if (this.hasDiscardButtonTarget) this.discardButtonTarget.hidden = false;
    this.syncActionState();
  }

  renderIdleState() {
    if (this.hasStartButtonTarget) this.startButtonTarget.hidden = false;
    if (this.hasStopButtonTarget) {
      this.stopButtonTarget.hidden = true;
      this.stopButtonTarget.disabled = false;
    }
    if (this.hasLiveTarget) this.liveTarget.hidden = true;
    if (this.hasPreviewTarget) this.previewTarget.hidden = true;
    if (this.hasSaveButtonTarget) this.saveButtonTarget.hidden = true;
    if (this.hasDiscardButtonTarget) this.discardButtonTarget.hidden = true;
    if (this.hasTimerTarget) this.timerTarget.textContent = "00:00";
    this.syncActionState();
  }

  canRecordInBrowser() {
    return Boolean(navigator.mediaDevices?.getUserMedia && this.mediaRecorderClass());
  }

  mediaRecorderClass() {
    return globalThis.MediaRecorder || window.MediaRecorder || null;
  }

  setFeedback(message) {
    if (!this.hasFeedbackTarget) {
      return;
    }

    this.feedbackTarget.textContent = message;
  }

  expandPanel() {
    if (!this.hasPanelTarget || this.panelTarget.classList.contains("show")) {
      return;
    }

    const collapse = globalThis.bootstrap?.Collapse;

    if (collapse?.getOrCreateInstance) {
      collapse.getOrCreateInstance(this.panelTarget).show();
    } else {
      this.panelTarget.classList.add("show");
    }

    const toggleButton = this.element.querySelector(`[data-bs-target="#${this.panelTarget.id}"]`);
    if (!toggleButton) {
      return;
    }

    toggleButton.setAttribute("aria-expanded", "true");
    toggleButton.setAttribute("title", "Collapse section");
  }

  openFallbackCapture() {
    if (!this.hasFallbackInputTarget) {
      this.setFeedback("Voice recording is not available in this browser.");
      return;
    }

    this.setFeedback("Opening your device recorder...");
    this.fallbackInputTarget.value = "";

    if (typeof this.fallbackInputTarget.showPicker === "function") {
      try {
        this.fallbackInputTarget.showPicker();
        return;
      } catch (_error) {
        // Fall through to click for browsers that block showPicker here.
      }
    }

    this.fallbackInputTarget.click();
  }

  stopStream() {
    if (!this.stream) {
      return;
    }

    this.stream.getTracks().forEach((track) => track.stop());
    this.stream = null;
    this.mediaRecorder = null;
  }

  formatDuration(durationSeconds) {
    const minutes = Math.floor(durationSeconds / 60);
    const seconds = durationSeconds % 60;
    return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
  }

  formatBytes(bytes) {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || "";
  }

  async audioDurationFor(previewUrl) {
    return new Promise((resolve) => {
      const audio = document.createElement("audio");
      const finalize = (value) => {
        audio.removeAttribute("src");
        audio.load();
        resolve(Number.isFinite(value) ? Math.max(Math.round(value), 0) : 0);
      };

      audio.preload = "metadata";
      audio.addEventListener("loadedmetadata", () => finalize(audio.duration), { once: true });
      audio.addEventListener("error", () => finalize(0), { once: true });
      audio.src = previewUrl;
    });
  }

  submitClosestForm() {
    const form = this.element.closest("form");
    if (!form) {
      return;
    }

    this.setFeedback("Creating your daily page...");
    form.requestSubmit();
  }

  microphoneAccessErrorMessage(error) {
    if (error?.name === "NotAllowedError" || error?.name === "SecurityError") {
      return "Microphone access was blocked. Allow microphone access and try again.";
    }

    if (error?.name === "NotFoundError" || error?.name === "DevicesNotFoundError") {
      return "No microphone was found on this device.";
    }

    return "Microphone access could not be started right now.";
  }

  syncActionState() {
    if (this.hasStartButtonTarget) this.startButtonTarget.disabled = this.isSaving;
    if (this.hasSaveButtonTarget) this.saveButtonTarget.disabled = this.isSaving;
    if (this.hasDiscardButtonTarget) this.discardButtonTarget.disabled = this.isSaving;
    if (this.hasFallbackInputTarget) this.fallbackInputTarget.disabled = this.isSaving;
  }
}
