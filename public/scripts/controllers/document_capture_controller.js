import { Controller } from "/scripts/vendor/stimulus.js";

// ── Stimulus Controller ───────────────────────────────────────────────────────
export default class extends Controller {
  static targets = [
    "overlay", "stageBar",
    "screen1", "screen2", "screen3", "screen4",
    "video", "drawCanvas", "camContainer", "cameraFallback", "flashOverlay", "flashBtn", "flashHint", "nativeCameraInput",
    "camStatus", "autoDot", "autoLabel", "autoCapLabel", "autoBadge", "fileInput",
    "detectContainer", "detectCanvas", "quadSvg", "cornerHandle", "loupeCanvas", "detectHint",
    "enhanceCanvas", "filterStrip", "brightness", "contrast", "brightnessVal", "contrastVal",
    "reviewCanvas", "reviewStats", "reviewTitle", "reviewTags", "saveBtn",
    "viewer", "viewerTitle", "viewerText",
    "count", "draftPayloadField", "draftList", "draftEmptyState"
  ];

  static values = {
    postUrl: String,
    csrf: String,
    mode: String
  };

  // ── Lifecycle ───────────────────────────────────────────────────────────────
  connect() {
    this.currentScreen = 0;
    this.autoCapture = true;
    this.capturedImage = null;
    this.croppedCanvas = null;
    this.enhancedCanvas = null;
    this.currentFilter = "auto";
    this.corners = [{ x: .1, y: .1 }, { x: .9, y: .1 }, { x: .9, y: .9 }, { x: .1, y: .9 }];
    this.draggingCornerIdx = -1;
    this.stableCount = 0;
    this.autoCaptureTriggered = false;
    this._flashOn = false;
    this._torchSupported = false;
    this._torchActive = false;
    this._stillFlashSupported = false;
    this._draftDocuments = this._readDraftDocuments();
    this._loadOpenCV();
    this._setupCornerDrag();
    this._syncFlashButton();
    this._renderDraftDocuments();
  }

  disconnect() {
    this._stopCamera();
  }

  _loadOpenCV() {
    if (window.__opencvReady) return;
    if (!document.querySelector('script[src*="opencv"]')) {
      const s = document.createElement("script");
      s.async = true;
      s.src = "https://docs.opencv.org/4.x/opencv.js";
      s.onload = () => { window.__opencvReady = true; };
      document.head.appendChild(s);
    }
  }

  // ── Overlay open/close ──────────────────────────────────────────────────────
  async open(event) {
    event?.preventDefault();

    const handledByNativeScanner = await this._openWithNativeDocumentScanner();
    if (handledByNativeScanner) return;

    this.overlayTarget.removeAttribute("aria-hidden");
    this.overlayTarget.classList.add("dcap-overlay--open");
    document.body.style.overflow = "hidden";
    this._showScreen(1);
    this._startCamera();
  }

  close() {
    this._stopCamera();
    this.overlayTarget.setAttribute("aria-hidden", "true");
    this.overlayTarget.classList.remove("dcap-overlay--open");
    document.body.style.overflow = "";
    this.currentScreen = 0;
  }

  _isDraftMode() {
    return this.modeValue === "draft" || this.hasDraftPayloadFieldTarget;
  }

  _readDraftDocuments() {
    if (!this.hasDraftPayloadFieldTarget) return [];

    try {
      const parsed = JSON.parse(this.draftPayloadFieldTarget.value || "[]");
      return Array.isArray(parsed) ? parsed.filter(doc => doc && typeof doc === "object") : [];
    } catch {
      return [];
    }
  }

  _writeDraftDocuments(documents) {
    this._draftDocuments = documents;

    if (this.hasDraftPayloadFieldTarget) {
      this.draftPayloadFieldTarget.value = JSON.stringify(documents);
    }

    this._renderDraftDocuments();
  }

  _renderDraftDocuments() {
    if (!this.hasDraftListTarget) return;

    const documents = this._draftDocuments || [];

    if (this.hasCountTarget) {
      this.countTarget.textContent = String(documents.length);
    }

    this.draftListTarget.hidden = documents.length === 0;
    if (this.hasDraftEmptyStateTarget) {
      this.draftEmptyStateTarget.hidden = documents.length > 0;
    }

    this.draftListTarget.innerHTML = documents.map((doc, index) => `
      <div class="sdoc-card">
        <div class="sdoc-accent-bar"></div>
        <div class="sdoc-inner">
          <div class="sdoc-header">
            <div class="sdoc-title">${this._escapeHtml(doc.title || "Untitled scan")}</div>
            <div class="sdoc-meta">
              <span class="sdoc-engine-label">PDF queued · pending save</span>
            </div>
          </div>

          <div class="sdoc-body">
            ${doc.image_data
              ? `<img src="${this._escapeAttribute(doc.image_data)}" class="sdoc-thumb" alt="${this._escapeAttribute(doc.title || "Untitled scan")}">`
              : `<div class="sdoc-thumb sdoc-thumb--placeholder"><i class="ti ti-file-text" aria-hidden="true"></i></div>`}
            <p class="sdoc-excerpt">OCR will be available after this scan is saved.</p>
          </div>

          <div class="sdoc-actions">
            <button
              type="button"
              class="btn btn-white btn-sm sdoc-delete-btn"
              data-action="click->document-capture#removeDraftDocument"
              data-index="${index}"
              title="Remove pending scan"
            ><i class="ti ti-trash" aria-hidden="true"></i><span class="sr-only">Delete</span></button>
          </div>
        </div>
      </div>
    `).join("");
  }

  removeDraftDocument(event) {
    const index = Number(event.currentTarget.dataset.index);
    if (Number.isNaN(index)) return;

    const documents = [...(this._draftDocuments || [])];
    documents.splice(index, 1);
    this._writeDraftDocuments(documents);
  }

  _escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll("\"", "&quot;")
      .replaceAll("'", "&#39;");
  }

  _escapeAttribute(value) {
    return this._escapeHtml(value).replaceAll("`", "&#96;");
  }

  _defaultScanTitle(date = new Date()) {
    return `Scan — ${date.toLocaleString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hour12: false
    })}`;
  }

  // ── Screen navigation ───────────────────────────────────────────────────────
  _showScreen(n) {
    [1, 2, 3, 4].forEach(i => {
      const el = this[`screen${i}Target`];
      el.hidden = (i !== n);
    });
    this.currentScreen = n;
    this.stageBarTarget.querySelectorAll(".dcap-stage-pill").forEach((pill, i) => {
      pill.classList.toggle("dcap-stage--done", i + 1 < n);
      pill.classList.toggle("dcap-stage--active", i + 1 === n);
    });
  }

  goToScreen1() { this._showScreen(1); this._startCamera(); }
  goToScreen2() { this._showScreen(2); this._renderDetectCanvas(); }
  goToScreen3() { this._showScreen(3); }
  goToScreen4() { this._showScreen(4); this._setupReviewScreen(); }

  // ── Camera ──────────────────────────────────────────────────────────────────
  async _startCamera() {
    this._stopCamera();
    this.stableCount = 0;
    this.autoCaptureTriggered = false;
    this._setCameraFallbackVisible(false);
    this._setCameraUIVisible(true);

    // mediaDevices is only available on secure contexts (HTTPS or localhost)
    if (!navigator.mediaDevices?.getUserMedia) {
      this._showCameraFallback("unavailable");
      this._updateAutoBadge();
      return;
    }

    // Check permission status first if the API is available
    try {
      const status = await navigator.permissions.query({ name: "camera" });
      if (status.state === "denied") {
        this._showCameraFallback("denied");
        this._updateAutoBadge();
        return;
      }
    } catch { /* permissions API not supported — fall through and try anyway */ }

    try {
      this._stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "environment", width: { ideal: 1280 }, height: { ideal: 720 } }
      });
      this.videoTarget.srcObject = this._stream;
      this.videoTarget.onloadedmetadata = () => {
        this.videoTarget.play();
        this._startDetectionLoop();
      };
      await this._refreshFlashSupport();
    } catch(err) {
      const type = err.name === "NotFoundError" || err.name === "DevicesNotFoundError"
        ? "notfound"
        : err.name === "NotAllowedError" || err.name === "PermissionDeniedError"
        ? "denied"
        : "unavailable";
      this._showCameraFallback(type);
    }
    this._updateAutoBadge();
  }

  async retryCamera() {
    this._setCameraFallbackVisible(false);
    this._setCameraUIVisible(true);
    await this._startCamera();
  }

  _stopCamera() {
    if (this._stream) { this._stream.getTracks().forEach(t => t.stop()); this._stream = null; }
    if (this._detectionTimer) { clearInterval(this._detectionTimer); this._detectionTimer = null; }
    if (this._simTimer) { clearTimeout(this._simTimer); this._simTimer = null; }
    if (this.hasVideoTarget) {
      this.videoTarget.pause?.();
      this.videoTarget.srcObject = null;
      this.videoTarget.onloadedmetadata = null;
    }
    if (this.hasCamStatusTarget) {
      this.camStatusTarget.textContent = "Align document within the frame";
      this.camStatusTarget.classList.remove("dcap-status--detected");
    }
    this._clearCanvas(this.drawCanvasTarget);
    this._torchSupported = false;
    this._torchActive = false;
    this._stillFlashSupported = false;
    this._syncFlashButton();
  }

  _getVideoTrack() {
    return this._stream?.getVideoTracks?.()?.[0] || null;
  }

  async _refreshFlashSupport() {
    const track = this._getVideoTrack();
    this._torchSupported = this._detectTorchSupport(track);
    this._stillFlashSupported = await this._detectStillFlashSupport(track);
    this._torchActive = false;

    if (this._flashOn) {
      if (this._torchSupported) {
        this._torchActive = await this._applyTorchState(true);
      }

      this._flashOn = this._torchActive || this._stillFlashSupported || this._supportsNativeCameraFlashFallback();
    }

    this._syncFlashButton();
  }

  _detectTorchSupport(track) {
    if (!track) return false;

    const capabilities = track.getCapabilities?.() || {};
    if (typeof capabilities.torch === "boolean") return capabilities.torch;

    return false;
  }

  async _detectStillFlashSupport(track) {
    if (!track) return false;
    if (typeof window.ImageCapture !== "function") return false;

    try {
      const imageCapture = new window.ImageCapture(track);
      const photoCapabilities = await imageCapture.getPhotoCapabilities?.();
      return Array.isArray(photoCapabilities?.fillLightMode)
        && photoCapabilities.fillLightMode.some((mode) => mode === "flash" || mode === "on");
    } catch {
      return false;
    }
  }

  _hasFlashSupport() {
    return this._hasBrowserFlashSupport() || this._supportsNativeCameraFlashFallback();
  }

  _hasBrowserFlashSupport() {
    return this._torchSupported || this._stillFlashSupported;
  }

  _supportsNativeCameraFlashFallback() {
    if (!this.hasNativeCameraInputTarget) return false;

    const userAgent = navigator.userAgent || "";
    const mobileUserAgent = /Android|iPhone|iPad|iPod|Mobile/i.test(userAgent);
    const coarsePointer = typeof window.matchMedia === "function"
      ? window.matchMedia("(pointer: coarse)").matches
      : false;

    return Boolean(navigator.userAgentData?.mobile || mobileUserAgent || coarsePointer || navigator.maxTouchPoints > 1);
  }

  async _applyTorchState(enabled) {
    const track = this._getVideoTrack();
    if (!track?.applyConstraints) return false;

    const constraintAttempts = [
      { advanced: [{ torch: enabled }] },
      { torch: enabled }
    ];

    for (const constraints of constraintAttempts) {
      try {
        await track.applyConstraints(constraints);
        const appliedState = track.getSettings?.().torch;
        if (typeof appliedState === "boolean" && appliedState !== enabled) continue;
        return true;
      } catch {
        // Try the next constraint shape for browsers that implement torch differently.
      }
    }

    return false;
  }

  _syncFlashButton() {
    if (!this.hasFlashBtnTarget) return;

    const button = this.flashBtnTarget;
    const supported = this._hasFlashSupport();
    const active = this._flashOn && supported;
    const usingNativeFallback = !this._hasBrowserFlashSupport() && this._supportsNativeCameraFlashFallback();

    button.style.visibility = supported ? "visible" : "hidden";
    button.disabled = !supported;
    button.innerHTML = '<i class="ti ti-bolt" aria-hidden="true"></i>';
    button.classList.toggle("dcap-icon-btn--active", active);
    button.setAttribute("aria-label", supported ? (active ? "Flash on" : "Flash off") : "Flash unavailable");
    button.setAttribute("aria-pressed", active ? "true" : "false");
    button.title = supported
      ? usingNativeFallback
        ? (active ? "Flash will use the device camera app on capture" : "Use the device camera app for flash")
        : (active ? "Turn flash off" : "Turn flash on")
      : "Flash unavailable on this camera";

    if (!this.hasFlashHintTarget) return;

    let note = "";
    if (usingNativeFallback) {
      note = "Flash may open your device camera app when you capture.";
    } else if (active && this._stillFlashSupported && !this._torchActive) {
      note = "Flash will fire when the photo is taken.";
    }

    this.flashHintTarget.hidden = note.length === 0;
    this.flashHintTarget.textContent = note;
  }

  _setCameraUIVisible(visible) {
    if (this.hasVideoTarget) this.videoTarget.hidden = !visible;
    if (this.hasDrawCanvasTarget) this.drawCanvasTarget.hidden = !visible;
    if (this.hasFlashOverlayTarget) this.flashOverlayTarget.hidden = !visible;
    if (this.hasCamStatusTarget) this.camStatusTarget.hidden = !visible;
    if (this.hasAutoBadgeTarget) this.autoBadgeTarget.hidden = !visible;
    this.camContainerTarget.querySelector(".dcap-cam-frame")?.toggleAttribute("hidden", !visible);
  }

  _setCameraFallbackVisible(visible, html = "") {
    if (!this.hasCameraFallbackTarget) return;

    this.cameraFallbackTarget.hidden = !visible;
    this.cameraFallbackTarget.innerHTML = visible ? html : "";
  }

  _showCameraFallback(type = "unavailable") {
    const messages = {
      denied: {
        icon: '<i class="ti ti-lock" aria-hidden="true"></i>',
        title: "Camera access blocked",
        sub: "Allow camera access in your browser, then tap Retry.",
        showRetry: true
      },
      notfound: {
        icon: '<i class="ti ti-camera" aria-hidden="true"></i>',
        title: "No camera found",
        sub: "Upload a photo or pick a sample document instead.",
        showRetry: false
      },
      unavailable: {
        icon: '<i class="ti ti-camera" aria-hidden="true"></i>',
        title: "Camera not available",
        sub: "Upload a photo or pick a sample document instead.",
        showRetry: false
      }
    };

    const { icon, title, sub, showRetry } = messages[type] || messages.unavailable;
    // No camera → flash is meaningless
    this._torchSupported = false;
    this._stillFlashSupported = false;
    this._syncFlashButton();
    this._setCameraUIVisible(false);
    this._setCameraFallbackVisible(true, `
      <div class="dcap-fallback">
        <div class="dcap-fallback-icon">${icon}</div>
        <div class="dcap-fallback-title">${title}</div>
        <div class="dcap-fallback-sub">${sub}</div>
        ${showRetry ? `
        <button class="dcap-retry-btn" data-action="click->document-capture#retryCamera">
          Retry camera
        </button>` : ""}
        <div class="dcap-samples">
          ${this._sampleLabels().map((l, i) => `
            <button class="dcap-sample-btn" data-action="click->document-capture#useSample" data-idx="${i}">
              ${l}
            </button>`).join("")}
        </div>
        ${this._supportsNativeCameraFlashFallback() ? `
        <button class="btn btn-white btn-sm" data-action="click->document-capture#openNativeCamera"><i class="ti ti-camera" aria-hidden="true"></i> Camera app</button>` : ""}
        <button class="btn btn-white btn-sm" data-action="click->document-capture#pickGallery"><i class="ti ti-photo-plus" aria-hidden="true"></i> Upload</button>
      </div>`);
  }

  _sampleLabels() { return ["Meeting Notes", "Invoice", "Research Notes"]; }

  _startDetectionLoop() {
    this._detectionTimer = setInterval(() => this._detectFrame(), 400);
    // Simulate detection after 2.5s as fallback if OpenCV not loaded
    this._simTimer = setTimeout(() => {
      if (this.currentScreen !== 1) return;
      this._onDocumentDetected([{ x: .08, y: .12 }, { x: .92, y: .08 }, { x: .93, y: .88 }, { x: .07, y: .92 }]);
    }, 2500);
  }

  _detectFrame() {
    if (this.currentScreen !== 1) return;
    const video = this.videoTarget;
    if (!video.readyState || video.readyState < 2) return;
    if (!window.__opencvReady || typeof cv === "undefined" || !cv.imread) return;

    const proc = document.createElement("canvas");
    proc.width = video.videoWidth || 640;
    proc.height = video.videoHeight || 480;
    proc.getContext("2d").drawImage(video, 0, 0);

    try {
      const src = cv.imread(proc);
      const gray = new cv.Mat(), blur = new cv.Mat(), edges = new cv.Mat();
      cv.cvtColor(src, gray, cv.COLOR_RGBA2GRAY);
      cv.GaussianBlur(gray, blur, new cv.Size(5, 5), 0);
      cv.Canny(blur, edges, 75, 200);

      const contours = new cv.MatVector(), hier = new cv.Mat();
      cv.findContours(edges, contours, hier, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);

      let best = null, bestArea = 0;
      const minArea = proc.width * proc.height * 0.15;
      for (let i = 0; i < contours.size(); i++) {
        const cnt = contours.get(i);
        const area = cv.contourArea(cnt);
        if (area < minArea) { cnt.delete(); continue; }
        const peri = cv.arcLength(cnt, true);
        const approx = new cv.Mat();
        cv.approxPolyDP(cnt, approx, 0.02 * peri, true);
        if (approx.rows === 4 && area > bestArea) {
          bestArea = area;
          best = [];
          for (let j = 0; j < 4; j++) {
            best.push({ x: approx.data32S[j * 2] / proc.width, y: approx.data32S[j * 2 + 1] / proc.height });
          }
        }
        approx.delete(); cnt.delete();
      }
      [src, gray, blur, edges, contours, hier].forEach(m => m.delete());

      if (best) {
        if (this._simTimer) { clearTimeout(this._simTimer); this._simTimer = null; }
        this._onDocumentDetected(this._orderQuad(best));
      } else {
        this.stableCount = 0;
        this.camStatusTarget.textContent = "Align document within the frame";
        this.camStatusTarget.classList.remove("dcap-status--detected");
        this._clearCanvas(this.drawCanvasTarget);
      }
    } catch {}
  }

  _orderQuad(pts) {
    const sorted = [...pts].sort((a, b) => a.y - b.y);
    const top = sorted.slice(0, 2).sort((a, b) => a.x - b.x);
    const bot = sorted.slice(2).sort((a, b) => b.x - a.x);
    return [top[0], top[1], bot[0], bot[1]];
  }

  _onDocumentDetected(quad) {
    this._detectedQuad = quad;
    this.camStatusTarget.textContent = "Document detected!";
    this.camStatusTarget.classList.add("dcap-status--detected");
    this._drawQuadOnCamera(quad);
    this.stableCount++;
    if (this.autoCapture && this.stableCount >= 4 && !this.autoCaptureTriggered) {
      this.autoCaptureTriggered = true;
      setTimeout(() => this.captureFrame(), 600);
    }
  }

  _drawQuadOnCamera(quad) {
    const canvas = this.drawCanvasTarget;
    const video = this.videoTarget;
    canvas.width = video.clientWidth || 360;
    canvas.height = video.clientHeight || 480;
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const w = canvas.width, h = canvas.height;
    ctx.beginPath();
    ctx.moveTo(quad[0].x * w, quad[0].y * h);
    for (let i = 1; i < 4; i++) ctx.lineTo(quad[i].x * w, quad[i].y * h);
    ctx.closePath();
    ctx.strokeStyle = "#2eaa60"; ctx.lineWidth = 3;
    ctx.shadowColor = "rgba(46,170,96,.5)"; ctx.shadowBlur = 8;
    ctx.stroke();
    ctx.shadowBlur = 0;
    quad.forEach(p => {
      ctx.beginPath();
      ctx.arc(p.x * w, p.y * h, 7, 0, Math.PI * 2);
      ctx.fillStyle = "#2eaa60"; ctx.fill();
    });
  }

  _clearCanvas(c) { if (c) c.getContext("2d").clearRect(0, 0, c.width, c.height); }

  async captureFrame() {
    this.autoCaptureTriggered = false;
    if (this._flashOn && !this._torchActive && !this._stillFlashSupported && this._supportsNativeCameraFlashFallback()) {
      if (this.hasCamStatusTarget) {
        this.camStatusTarget.textContent = "Opening device camera for flash capture…";
      }
      this.openNativeCamera();
      return;
    }
    // Only fire the screen-flash animation when flash is enabled
    if (this._flashOn) {
      this.flashOverlayTarget.classList.add("dcap-flash--active");
      setTimeout(() => this.flashOverlayTarget.classList.remove("dcap-flash--active"), 180);
    }
    this.capturedImage = await this._captureCurrentFrame() || this._buildSampleCanvas(0);
    this._stopCamera();
    setTimeout(() => { this._showScreen(2); this._renderDetectCanvas(); }, 180);
  }

  async _captureCurrentFrame() {
    const track = this._getVideoTrack();
    if (this._flashOn && !this._torchActive && this._stillFlashSupported && track) {
      const stillPhoto = await this._captureStillPhotoWithFlash(track);
      if (stillPhoto) return stillPhoto;
    }

    return this._captureVideoFrame();
  }

  _captureVideoFrame() {
    const video = this.videoTarget;
    if (!(video?.srcObject) || video.readyState < 2) {
      return null;
    }

    const canvas = document.createElement("canvas");
    canvas.width = video.videoWidth || 640;
    canvas.height = video.videoHeight || 480;
    canvas.getContext("2d").drawImage(video, 0, 0);
    return canvas;
  }

  async _captureStillPhotoWithFlash(track) {
    if (typeof window.ImageCapture !== "function") return null;

    const flashModes = ["flash", "on"];

    try {
      const imageCapture = new window.ImageCapture(track);
      for (const fillLightMode of flashModes) {
        try {
          const blob = await imageCapture.takePhoto({ fillLightMode });
          const canvas = await this._canvasFromBlob(blob);
          if (canvas) return canvas;
        } catch {
          // Try the next flash mode for browsers with older ImageCapture implementations.
        }
      }
    } catch {
      return null;
    }

    return null;
  }

  async _canvasFromBlob(blob) {
    if (!(blob instanceof Blob)) return null;

    return await new Promise((resolve) => {
      const img = new Image();
      const url = URL.createObjectURL(blob);

      img.onload = () => {
        const canvas = document.createElement("canvas");
        canvas.width = img.naturalWidth;
        canvas.height = img.naturalHeight;
        canvas.getContext("2d").drawImage(img, 0, 0);
        URL.revokeObjectURL(url);
        resolve(canvas);
      };

      img.onerror = () => {
        URL.revokeObjectURL(url);
        resolve(null);
      };

      img.src = url;
    });
  }

  useSample(e) {
    const idx = parseInt(e.currentTarget.dataset.idx || 0);
    this.capturedImage = this._buildSampleCanvas(idx);
    this._stopCamera();
    this._showScreen(2);
    this._renderDetectCanvas();
  }

  openNativeCamera(event) {
    event?.preventDefault();

    if (!this.hasNativeCameraInputTarget) return;

    this.nativeCameraInputTarget.value = "";

    if (typeof this.nativeCameraInputTarget.showPicker === "function") {
      try {
        this.nativeCameraInputTarget.showPicker();
        return;
      } catch {
        // Fall back to click when the picker API is blocked.
      }
    }

    this.nativeCameraInputTarget.click();
  }

  pickGallery() { this.fileInputTarget.click(); }

  handleFile(e) {
    const file = e.target.files[0]; if (!file) return;
    const img = new Image();
    const url = URL.createObjectURL(file);
    img.onload = () => {
      const c = document.createElement("canvas");
      c.width = img.naturalWidth; c.height = img.naturalHeight;
      c.getContext("2d").drawImage(img, 0, 0);
      this.capturedImage = c;
      URL.revokeObjectURL(url);
      this._stopCamera();
      this._showScreen(2);
      this._renderDetectCanvas();
    };
    img.src = url;
  }

  _buildSampleCanvas(idx) {
    const samples = [
      { title: "Meeting Notes", lines: ["Q1 Review — April 11", "Attendees: Alex, Sam", "Revenue up 23% YoY", "Key driver: subscriptions", "Next: board presentation Q2"] },
      { title: "Invoice #4521", lines: ["Date: April 10, 2026", "From: Acme Corp", "To: InkCreate Ltd", "Amount: $3,200.00", "Due: April 30, 2026"] },
      { title: "Research Notes", lines: ["Topic: Document scanning", "Edge detect accuracy: 94%", "12 user test participants", "Task completion: 89%", "Avg scan time: 14 seconds"] }
    ];
    const s = samples[idx] || samples[0];
    const c = document.createElement("canvas"); c.width = 480; c.height = 640;
    const ctx = c.getContext("2d");
    ctx.fillStyle = "#fffdf8"; ctx.fillRect(0, 0, 480, 640);
    ctx.fillStyle = "#ff5f4e"; ctx.fillRect(0, 0, 480, 4);
    ctx.fillStyle = "#1b1b1d"; ctx.font = "bold 28px Inter,sans-serif";
    ctx.fillText(s.title, 28, 52);
    ctx.fillStyle = "#7a7670"; ctx.font = "18px Inter,sans-serif";
    s.lines.forEach((l, i) => ctx.fillText(l, 28, 100 + i * 36));
    return c;
  }

  async toggleFlash() {
    if (!this._hasFlashSupport() || !this._stream) {
      this._syncFlashButton();
      return;
    }

    const nextState = !this._flashOn;

    if (!nextState) {
      if (this._torchActive) {
        const disabled = await this._applyTorchState(false);
        if (!disabled) {
          this._syncFlashButton();
          return;
        }
      }

      this._torchActive = false;
      this._flashOn = false;
      this._syncFlashButton();
      return;
    }

    this._torchActive = false;
    if (this._torchSupported) {
      this._torchActive = await this._applyTorchState(true);
    }

    this._flashOn = this._torchActive || this._stillFlashSupported || this._supportsNativeCameraFlashFallback();
    this._syncFlashButton();
  }

  toggleAuto() {
    this.autoCapture = !this.autoCapture;
    this.autoCapLabelTarget.textContent = this.autoCapture ? "Auto ✓" : "Auto ✗";
    this._updateAutoBadge();
  }

  _updateAutoBadge() {
    if (!this.hasAutoDotTarget) return;
    this.autoDotTarget.classList.toggle("dcap-auto-dot--off", !this.autoCapture);
    this.autoLabelTarget.textContent = this.autoCapture ? "Auto" : "Manual";
  }

  // ── Stage 2: Corner adjustment ──────────────────────────────────────────────
  _renderDetectCanvas() {
    const container = this.detectContainerTarget;
    const canvas = this.detectCanvasTarget;
    const src = this.capturedImage;
    if (!src) return;
    const maxW = container.clientWidth || 360;
    const maxH = Math.min(container.clientHeight || 520, 520);
    const scale = Math.min(maxW / src.width, maxH / src.height, 1);
    canvas.width = Math.round(src.width * scale);
    canvas.height = Math.round(src.height * scale);
    canvas.style.width = canvas.width + "px";
    canvas.style.height = canvas.height + "px";
    canvas.getContext("2d").drawImage(src, 0, 0, canvas.width, canvas.height);
    this.corners = this._detectedQuad
      ? this._detectedQuad.map(p => ({ ...p }))
      : [{ x: .1, y: .1 }, { x: .9, y: .1 }, { x: .9, y: .9 }, { x: .1, y: .9 }];
    this.detectHintTarget.textContent = this._detectedQuad
      ? "Document detected — adjust if needed"
      : "Drag corners to select the document area";
    this._updateCornerHandles();
    this._drawQuadSVG();
  }

  _updateCornerHandles() {
    const canvas = this.detectCanvasTarget;
    const rect = canvas.getBoundingClientRect();
    this.cornerHandleTargets.forEach((el, i) => {
      el.style.left = (rect.left - this.element.getBoundingClientRect().left + this.corners[i].x * rect.width) + "px";
      el.style.top = (rect.top - this.element.getBoundingClientRect().top + this.corners[i].y * rect.height) + "px";
    });
  }

  _drawQuadSVG() {
    const canvas = this.detectCanvasTarget;
    const rect = canvas.getBoundingClientRect();
    const cRect = this.detectContainerTarget.getBoundingClientRect();
    const svg = this.quadSvgTarget;
    svg.style.left = (rect.left - cRect.left) + "px";
    svg.style.top = (rect.top - cRect.top) + "px";
    svg.style.width = rect.width + "px";
    svg.style.height = rect.height + "px";
    svg.setAttribute("viewBox", `0 0 ${rect.width} ${rect.height}`);
    const pts = this.corners.map(c => `${c.x * rect.width},${c.y * rect.height}`).join(" ");
    svg.innerHTML = `<polygon points="${pts}" fill="rgba(255,95,78,.1)" stroke="#ff5f4e" stroke-width="2.5" stroke-dasharray="6,3"/>`;
  }

  _setupCornerDrag() {
    // Delegated pointer events on the element
    this.element.addEventListener("pointerdown", e => {
      const handle = e.target.closest("[data-document-capture-target='cornerHandle']");
      if (!handle) return;
      e.preventDefault();
      this.draggingCornerIdx = parseInt(handle.dataset.idx);
      handle.classList.add("dcap-handle--dragging");
      handle.setPointerCapture(e.pointerId);
    });
    this.element.addEventListener("pointermove", e => {
      if (this.draggingCornerIdx < 0) return;
      const canvas = this.detectCanvasTarget;
      const rect = canvas.getBoundingClientRect();
      this.corners[this.draggingCornerIdx] = {
        x: Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width)),
        y: Math.max(0, Math.min(1, (e.clientY - rect.top) / rect.height))
      };
      this._updateCornerHandles();
      this._drawQuadSVG();
      this._showLoupe(this.draggingCornerIdx, e.clientX, e.clientY);
    });
    this.element.addEventListener("pointerup", e => {
      if (this.draggingCornerIdx >= 0) {
        const handle = this.cornerHandleTargets[this.draggingCornerIdx];
        handle?.classList.remove("dcap-handle--dragging");
      }
      this.draggingCornerIdx = -1;
      if (this.hasLoupeCanvasTarget) this.loupeCanvasTarget.style.display = "none";
    });
  }

  _showLoupe(idx, cx, cy) {
    const loupe = this.loupeCanvasTarget;
    const src = this.detectCanvasTarget;
    const rect = src.getBoundingClientRect();
    const cRect = this.detectContainerTarget.getBoundingClientRect();
    const px = this.corners[idx].x * src.width;
    const py = this.corners[idx].y * src.height;
    const r = 40, ds = loupe.width = loupe.height = 80;
    const ctx = loupe.getContext("2d");
    ctx.clearRect(0, 0, ds, ds);
    ctx.save(); ctx.beginPath(); ctx.arc(40, 40, 38, 0, Math.PI * 2); ctx.clip();
    ctx.drawImage(src, px - r, py - r, r * 2, r * 2, 0, 0, ds, ds);
    ctx.restore();
    ctx.beginPath(); ctx.moveTo(40, 30); ctx.lineTo(40, 50); ctx.moveTo(30, 40); ctx.lineTo(50, 40);
    ctx.strokeStyle = "rgba(255,95,78,.8)"; ctx.lineWidth = 2; ctx.stroke();
    loupe.style.display = "block";
    loupe.style.left = (cx - cRect.left - 40) + "px";
    loupe.style.top = (cy - cRect.top - 92) + "px";
  }

  resetCorners() {
    this.corners = [{ x: .1, y: .1 }, { x: .9, y: .1 }, { x: .9, y: .9 }, { x: .1, y: .9 }];
    this._updateCornerHandles();
    this._drawQuadSVG();
  }

  // ── Stage 3: Crop + enhance ─────────────────────────────────────────────────
  cropAndEnhance() {
    this._doCrop();
    this._showScreen(3);
    this._buildFilterStrip();
    this._applyFilter(this.currentFilter);
  }

  _doCrop() {
    const src = this.capturedImage;
    if (!src) return;
    if (window.__opencvReady && typeof cv !== "undefined" && cv.getPerspectiveTransform) {
      try {
        const tmp = document.createElement("canvas");
        tmp.width = src.width; tmp.height = src.height;
        tmp.getContext("2d").drawImage(src, 0, 0);
        const mat = cv.imread(tmp);
        const W = tmp.width, H = tmp.height;
        const outW = 480, outH = 640;
        const srcPts = cv.matFromArray(4, 1, cv.CV_32FC2, [
          this.corners[0].x * W, this.corners[0].y * H,
          this.corners[1].x * W, this.corners[1].y * H,
          this.corners[2].x * W, this.corners[2].y * H,
          this.corners[3].x * W, this.corners[3].y * H
        ]);
        const dstPts = cv.matFromArray(4, 1, cv.CV_32FC2, [0, 0, outW, 0, outW, outH, 0, outH]);
        const M = cv.getPerspectiveTransform(srcPts, dstPts);
        const out = new cv.Mat();
        cv.warpPerspective(mat, out, M, new cv.Size(outW, outH));
        const outCanvas = document.createElement("canvas");
        outCanvas.width = outW; outCanvas.height = outH;
        cv.imshow(outCanvas, out);
        [mat, srcPts, dstPts, M, out].forEach(m => m.delete());
        this.croppedCanvas = outCanvas;
        return;
      } catch {}
    }
    // Fallback: simple bbox crop
    const c = this.corners;
    const W = src.width, H = src.height;
    const x = Math.min(c[0].x, c[1].x, c[2].x, c[3].x) * W;
    const y = Math.min(c[0].y, c[1].y, c[2].y, c[3].y) * H;
    const w = (Math.max(c[0].x, c[1].x, c[2].x, c[3].x) - Math.min(c[0].x, c[1].x, c[2].x, c[3].x)) * W;
    const h = (Math.max(c[0].y, c[1].y, c[2].y, c[3].y) - Math.min(c[0].y, c[1].y, c[2].y, c[3].y)) * H;
    const out = document.createElement("canvas");
    out.width = Math.max(1, Math.round(w)); out.height = Math.max(1, Math.round(h));
    out.getContext("2d").drawImage(src, x, y, w, h, 0, 0, out.width, out.height);
    this.croppedCanvas = out;
  }

  _buildFilterStrip() {
    const strip = this.filterStripTarget;
    strip.innerHTML = "";
    const filters = [
      { id: "original", name: "Original" },
      { id: "auto", name: "Auto" },
      { id: "gray", name: "Grayscale" },
      { id: "bw", name: "B&W Doc" },
      { id: "color", name: "Color+" },
      { id: "lighten", name: "Lighten" }
    ];
    filters.forEach(f => {
      const chip = document.createElement("div");
      chip.className = "dcap-filter-chip" + (f.id === this.currentFilter ? " dcap-filter-chip--active" : "");
      chip.dataset.filterId = f.id;
      chip.addEventListener("click", () => this._applyFilter(f.id));
      const thumbC = document.createElement("canvas"); thumbC.width = 56; thumbC.height = 72;
      if (this.croppedCanvas) {
        const ctx = thumbC.getContext("2d");
        ctx.drawImage(this.croppedCanvas, 0, 0, thumbC.width, thumbC.height);
        if (f.id !== "original") {
          const imgd = ctx.getImageData(0, 0, thumbC.width, thumbC.height);
          this._processFilter(imgd, f.id, 0, 0);
          ctx.putImageData(imgd, 0, 0);
        }
      }
      const check = document.createElement("div");
      check.className = "dcap-filter-check";
      check.innerHTML = `<svg width="20" height="20" viewBox="0 0 20 20"><path d="M4 10l5 5 7-8" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/></svg>`;
      const wrap = document.createElement("div"); wrap.className = "dcap-filter-thumb";
      wrap.appendChild(thumbC); wrap.appendChild(check);
      const name = document.createElement("div"); name.className = "dcap-filter-name"; name.textContent = f.name;
      chip.appendChild(wrap); chip.appendChild(name);
      strip.appendChild(chip);
    });
  }

  _processFilter(imgd, id, brightness, contrast) {
    const d = imgd.data;
    const bc = v => {
      let r = (v / 255 - 0.5) * ((contrast + 100) / 100) + 0.5 + (brightness / 255);
      return Math.max(0, Math.min(255, r * 255));
    };
    for (let i = 0; i < d.length; i += 4) {
      let r = d[i], g = d[i + 1], b = d[i + 2];
      switch (id) {
        case "gray":  { const l = 0.299 * r + 0.587 * g + 0.114 * b; r = g = b = l; break; }
        case "auto":  { const l = 0.299 * r + 0.587 * g + 0.114 * b; const f = l < 128 ? 1.15 : 0.95; r = Math.min(255, r * f + 8); g = Math.min(255, g * f + 8); b = Math.min(255, b * f + 8); break; }
        case "bw":    { const l = 0.299 * r + 0.587 * g + 0.114 * b; const v = l > 140 ? 255 : 0; r = g = b = v; break; }
        case "color": { r = Math.min(255, r * 1.12); g = Math.min(255, g * 1.08); b = Math.min(255, b * 0.92); break; }
        case "lighten": { r = Math.min(255, r + 40); g = Math.min(255, g + 40); b = Math.min(255, b + 40); break; }
      }
      if (brightness !== 0 || contrast !== 0) { r = bc(r); g = bc(g); b = bc(b); }
      d[i] = r; d[i + 1] = g; d[i + 2] = b;
    }
  }

  _applyFilter(filterId) {
    this.currentFilter = filterId;
    const bv = this.hasBrightnessTarget ? parseInt(this.brightnessTarget.value) : 0;
    const cv2 = this.hasContrastTarget ? parseInt(this.contrastTarget.value) : 0;
    const src = this.croppedCanvas; if (!src) return;
    const out = document.createElement("canvas");
    out.width = src.width; out.height = src.height;
    const ctx = out.getContext("2d");
    ctx.drawImage(src, 0, 0);
    if (filterId !== "original") {
      const imgd = ctx.getImageData(0, 0, out.width, out.height);
      this._processFilter(imgd, filterId, bv, cv2);
      ctx.putImageData(imgd, 0, 0);
    }
    this.enhancedCanvas = out;
    const display = this.enhanceCanvasTarget;
    display.width = out.width; display.height = out.height;
    display.getContext("2d").drawImage(out, 0, 0);
    this.filterStripTarget.querySelectorAll(".dcap-filter-chip").forEach(c => {
      c.classList.toggle("dcap-filter-chip--active", c.dataset.filterId === filterId);
    });
  }

  applyManual() {
    if (this.hasBrightnessValTarget) this.brightnessValTarget.textContent = this.brightnessTarget.value;
    if (this.hasContrastValTarget) this.contrastValTarget.textContent = this.contrastTarget.value;
    this._applyFilter(this.currentFilter);
  }

  rotateLeft() { this._rotate(-90); }
  rotateRight() { this._rotate(90); }
  flip() {
    const src = this.croppedCanvas; if (!src) return;
    const out = document.createElement("canvas"); out.width = src.width; out.height = src.height;
    const ctx = out.getContext("2d");
    ctx.translate(src.width, 0); ctx.scale(-1, 1); ctx.drawImage(src, 0, 0);
    this.croppedCanvas = out; this._applyFilter(this.currentFilter); this._buildFilterStrip();
  }

  _rotate(deg) {
    const src = this.croppedCanvas; if (!src) return;
    const rad = deg * Math.PI / 180;
    const nw = Math.abs(src.width * Math.cos(rad)) + Math.abs(src.height * Math.sin(rad));
    const nh = Math.abs(src.width * Math.sin(rad)) + Math.abs(src.height * Math.cos(rad));
    const out = document.createElement("canvas"); out.width = Math.round(nw); out.height = Math.round(nh);
    const ctx = out.getContext("2d");
    ctx.translate(out.width / 2, out.height / 2); ctx.rotate(rad); ctx.drawImage(src, -src.width / 2, -src.height / 2);
    this.croppedCanvas = out; this._applyFilter(this.currentFilter); this._buildFilterStrip();
  }

  // ── Stage 4: Review & save ─────────────────────────────────────────────────
  // ── Stage 4: Review ─────────────────────────────────────────────────────────
  _setupReviewScreen() {
    const src = this.enhancedCanvas || this.croppedCanvas;
    const rc = this.reviewCanvasTarget;
    if (src && rc) { rc.width = src.width; rc.height = src.height; rc.getContext("2d").drawImage(src, 0, 0); }
    this.reviewTitleTarget.value = this._defaultScanTitle();
    this.reviewTagsTarget.value = "";
    this.reviewStatsTarget.innerHTML = `
      <div class="dcap-stat"><div class="dcap-stat-label">Format</div><div class="dcap-stat-value">PDF</div></div>
      <div class="dcap-stat"><div class="dcap-stat-label">Filter</div><div class="dcap-stat-value">${this._filterDisplayName(this.currentFilter)}</div></div>
      <div class="dcap-stat"><div class="dcap-stat-label">Width</div><div class="dcap-stat-value">${src?.width || "—"} px</div></div>
      <div class="dcap-stat"><div class="dcap-stat-label">Height</div><div class="dcap-stat-value">${src?.height || "—"} px</div></div>`;
  }

  async save() {
    const btn = this.saveBtnTarget;
    btn.disabled = true;
    btn.textContent = "Saving…";
    const canvas = this.enhancedCanvas || this.croppedCanvas;
    if (!canvas) { btn.disabled = false; btn.textContent = "Save PDF"; return; }

    try {
      await this._saveScannedDocumentPayload(this._buildScannedDocumentPayload(canvas));
    } catch (error) {
      btn.disabled = false; btn.textContent = "Save PDF";
      alert(error?.message || "Network error. Please try again.");
    }
  }

  _buildScannedDocumentPayload(canvas) {
    return {
      title: this.reviewTitleTarget.value,
      enhancement_filter: this.currentFilter,
      tags: JSON.stringify(
        (this.reviewTagsTarget.value || "").split(",").map(tag => tag.trim()).filter(Boolean)
      ),
      image_data: canvas.toDataURL("image/jpeg", 0.92)
    };
  }

  async _saveScannedDocumentPayload(payload) {
    if (this._isDraftMode()) {
      this._writeDraftDocuments([payload, ...(this._draftDocuments || [])]);
      this.saveBtnTarget.disabled = false;
      this.saveBtnTarget.textContent = "Save PDF";
      this.close();
      return;
    }

    const formData = new FormData();
    formData.append("scanned_document[title]", payload.title || this._defaultScanTitle());
    formData.append("scanned_document[enhancement_filter]", payload.enhancement_filter || "auto");
    formData.append("scanned_document[tags]", payload.tags || "[]");
    if (payload.image_data) formData.append("scanned_document[image_data]", payload.image_data);
    if (payload.pdf_data) formData.append("scanned_document[pdf_data]", payload.pdf_data);

    const resp = await fetch(this.postUrlValue, {
      method: "POST",
      body: formData,
      headers: { "X-CSRF-Token": this.csrfValue, "X-Requested-With": "XMLHttpRequest" }
    });

    if (resp.ok || resp.redirected) {
      window.location.reload();
      return;
    }

    throw new Error("Save failed. Please try again.");
  }

  _filterDisplayName(filterId) {
    const map = {
      original: "Original",
      auto: "Auto",
      gray: "Grayscale",
      bw: "B&W Doc",
      color: "Color+",
      lighten: "Lighten"
    };

    return map[filterId] || "Auto";
  }

  async _openWithNativeDocumentScanner() {
    if (!this._shouldUseNativeDocumentScanner()) return false;

    try {
      const result = await this._runNativeDocumentScanner();
      if (this._isNativeDocumentScanCancelled(result)) return true;

      const payload = this._buildNativeScannedDocumentPayload(result);
      if (!payload.image_data) {
        throw new Error("Native scanner did not return a preview image.");
      }

      await this._saveScannedDocumentPayload(payload);
      return true;
    } catch (error) {
      if (this._isNativeDocumentScanCancelled(error)) return true;

      console.warn("Native document scanner failed, falling back to browser capture.", error);
      return false;
    }
  }

  _shouldUseNativeDocumentScanner() {
    return Boolean(this._isNativeAndroidApp() && this._nativeDocumentScannerPlugin());
  }

  _isNativeAndroidApp() {
    return this._capacitorPlatform() === "android" && this._isNativeCapacitorApp();
  }

  _capacitorPlatform() {
    const capacitor = window.Capacitor;
    if (!capacitor) return null;
    if (typeof capacitor.getPlatform === "function") return capacitor.getPlatform();
    return null;
  }

  _nativeDocumentScannerPlugin() {
    return window.InkcreateDocumentScanner
      || window.Capacitor?.Plugins?.InkcreateDocumentScanner
      || window.Capacitor?.Plugins?.NativeDocumentScanner
      || null;
  }

  async _runNativeDocumentScanner() {
    const plugin = this._nativeDocumentScannerPlugin();
    const runner = plugin?.scanDocument || plugin?.startScan || plugin?.openScanner;
    if (typeof runner !== "function") {
      throw new Error("Native document scanner plugin is unavailable.");
    }

    return runner.call(plugin, {
      formats: ["jpeg", "pdf"],
      pageLimit: 24,
      allowGalleryImport: true,
      scannerMode: "full"
    });
  }

  _isNativeDocumentScanCancelled(value) {
    if (!value) return false;
    if (value === "cancelled") return true;
    if (value?.cancelled === true || value?.canceled === true) return true;

    const message = value?.message || value?.error || value?.toString?.() || "";
    return /cancel/i.test(message);
  }

  _buildNativeScannedDocumentPayload(result) {
    const pages = Array.isArray(result?.pages) ? result.pages : [];
    const firstPage = pages[0] || null;
    const tags = Array.isArray(result?.tags) ? result.tags : [];

    return {
      title: result?.title || this._defaultScanTitle(),
      enhancement_filter: result?.enhancementFilter || "auto",
      tags: JSON.stringify(tags.filter(Boolean)),
      image_data: result?.previewImageDataUrl
        || result?.imageDataUrl
        || result?.preview?.dataUrl
        || firstPage?.imageDataUrl
        || firstPage?.previewImageDataUrl
        || firstPage?.dataUrl
        || "",
      pdf_data: result?.pdfDataUrl
        || result?.documentPdfDataUrl
        || result?.pdf?.dataUrl
        || ""
    };
  }

  openPdf(event) {
    const url = event.currentTarget.dataset.pdfUrl;
    if (!url) return;

    window.open(url, "_blank", "noopener");
  }

  async runOcr(event) {
    const trigger = event.currentTarget;
    if (!this._shouldUseNativeOcr(trigger)) return;

    event.preventDefault();

    const form = trigger.form;
    const originalMarkup = trigger.innerHTML;
    trigger.disabled = true;
    trigger.innerHTML = '<i class="ti ti-loader-2" aria-hidden="true"></i> Running…';

    try {
      const imageDataUrl = await this._fetchImageDataUrl(trigger.dataset.imageUrl);
      const plugin = this._nativeOcrPlugin();
      const result = await this._recognizeNativeText(plugin, {
        imageDataUrl,
        documentId: trigger.dataset.documentId,
        title: trigger.dataset.documentTitle || "Scanned document"
      });

      const response = await fetch(trigger.dataset.nativeOcrUrl, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfValue,
          "X-Requested-With": "XMLHttpRequest"
        },
        body: JSON.stringify({
          ocr_result: this._buildNativeOcrPayload(result)
        })
      });

      if (!response.ok) {
        const data = await response.json().catch(() => null);
        throw new Error(data?.error || "Could not save the OCR result.");
      }

      window.location.reload();
    } catch (error) {
      console.warn("Native OCR failed, falling back to server OCR.", error);

      if (form) {
        form.submit();
        return;
      }

      trigger.disabled = false;
      trigger.innerHTML = originalMarkup;
      alert(error?.message || "OCR failed. Please try again.");
    }
  }

  _shouldUseNativeOcr(trigger) {
    return Boolean(
      trigger &&
      this._isNativeCapacitorApp() &&
      this._nativeOcrPlugin() &&
      trigger.dataset.nativeOcrUrl &&
      trigger.dataset.imageUrl
    );
  }

  _isNativeCapacitorApp() {
    const capacitor = window.Capacitor;
    if (!capacitor) return false;
    if (typeof capacitor.isNativePlatform === "function") return capacitor.isNativePlatform();

    const platform = typeof capacitor.getPlatform === "function" ? capacitor.getPlatform() : null;
    return platform === "android" || platform === "ios";
  }

  _nativeOcrPlugin() {
    return window.InkcreateNativeOcr
      || window.Capacitor?.Plugins?.InkcreateNativeOcr
      || window.Capacitor?.Plugins?.NativeTextRecognition
      || null;
  }

  async _recognizeNativeText(plugin, payload) {
    const runner = plugin?.recognizeText || plugin?.runOcr;
    if (typeof runner !== "function") {
      throw new Error("Native OCR plugin is unavailable.");
    }

    return runner.call(plugin, payload);
  }

  async _fetchImageDataUrl(url) {
    const response = await fetch(url, {
      credentials: "same-origin",
      headers: {
        "Accept": "application/json",
        "X-Requested-With": "XMLHttpRequest"
      }
    });

    if (!response.ok) {
      throw new Error("Could not load the scanned document image.");
    }

    const data = await response.json().catch(() => null);
    if (!data?.image_data_url) {
      throw new Error(data?.error || "Could not prepare the scanned document image.");
    }

    return data.image_data_url;
  }

  _buildNativeOcrPayload(result) {
    const text = result?.text || result?.extractedText || result?.fullText || "";
    const confidence = result?.confidence ?? result?.meanConfidence ?? result?.confidencePercent ?? null;
    const language = result?.language || result?.languageCode || result?.detectedLanguage || null;
    const engine = result?.engine || "google-ml";

    return { text, confidence, language, engine };
  }

  // ── Text viewer ──────────────────────────────────────────────────────────────
  viewFull(e) {
    this.viewerTitleTarget.textContent = e.currentTarget.dataset.title || "Extracted text";
    this.viewerTextTarget.value = e.currentTarget.dataset.text || "";
    this.viewerTarget.hidden = false;
    this.overlayTarget.removeAttribute("aria-hidden");
    this.overlayTarget.classList.add("dcap-overlay--open");
    document.body.style.overflow = "hidden";
  }

  closeViewer() {
    this.viewerTarget.hidden = true;
    this.overlayTarget.classList.remove("dcap-overlay--open");
    this.overlayTarget.setAttribute("aria-hidden", "true");
    document.body.style.overflow = "";
  }

  copyViewer() {
    navigator.clipboard.writeText(this.viewerTextTarget.value)
      .then(() => { this.viewerTextTarget.style.borderColor = "#2eaa60"; setTimeout(() => this.viewerTextTarget.style.borderColor = "", 1200); })
      .catch(() => {});
  }

  copyText(e) {
    navigator.clipboard.writeText(e.currentTarget.dataset.text || "")
      .then(() => {
        e.currentTarget.innerHTML = '<i class="ti ti-check" aria-hidden="true"></i> Copied';
        setTimeout(() => {
          e.currentTarget.innerHTML = '<i class="ti ti-copy" aria-hidden="true"></i> Copy';
        }, 1500);
      })
      .catch(() => {});
  }
}
