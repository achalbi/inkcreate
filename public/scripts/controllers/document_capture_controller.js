import { Controller } from "/scripts/vendor/stimulus.js";

// ── Stimulus Controller ───────────────────────────────────────────────────────
export default class extends Controller {
  static targets = [
    "overlay", "stageBar",
    "screen1", "screen2", "screen3", "screen4",
    "video", "drawCanvas", "camContainer", "flashOverlay", "flashBtn",
    "camStatus", "autoDot", "autoLabel", "autoCapLabel", "autoBadge", "fileInput",
    "detectContainer", "detectCanvas", "quadSvg", "cornerHandle", "loupeCanvas", "detectHint",
    "enhanceCanvas", "filterStrip", "brightness", "contrast", "brightnessVal", "contrastVal",
    "reviewCanvas", "reviewStats", "reviewTitle", "reviewTags", "saveBtn",
    "viewer", "viewerTitle", "viewerText"
  ];

  static values = {
    postUrl: String,
    csrf: String
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
    this._loadDependencies();
    this._setupCornerDrag();
  }

  disconnect() {
    this._stopCamera();
  }

  _loadDependencies() {
    if (window.__opencvReady) return;
    if (!document.querySelector('script[src*="opencv"]')) {
      const s = document.createElement("script");
      s.async = true;
      s.src = "https://docs.opencv.org/4.x/opencv.js";
      s.onload = () => { window.__opencvReady = true; };
      document.head.appendChild(s);
    }
    if (!document.querySelector('script[src*="jspdf"]')) {
      const s = document.createElement("script");
      s.src = "https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js";
      document.head.appendChild(s);
    }
  }

  // ── Overlay open/close ──────────────────────────────────────────────────────
  open() {
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
      // Check if this device supports torch (rear camera flash)
      const track = this._stream.getVideoTracks()[0];
      const capabilities = track?.getCapabilities?.() || {};
      this._torchSupported = !!(capabilities.torch);
      if (this.hasFlashBtnTarget) {
        this.flashBtnTarget.style.visibility = this._torchSupported ? "visible" : "hidden";
      }
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
    this.camContainerTarget.innerHTML = "";
    await this._startCamera();
  }

  _stopCamera() {
    if (this._stream) { this._stream.getTracks().forEach(t => t.stop()); this._stream = null; }
    if (this._detectionTimer) { clearInterval(this._detectionTimer); this._detectionTimer = null; }
    if (this._simTimer) { clearTimeout(this._simTimer); this._simTimer = null; }
  }

  _showCameraFallback(type = "unavailable") {
    const container = this.camContainerTarget;

    const messages = {
      denied: {
        icon: "🔒",
        title: "Camera access blocked",
        sub: "Allow camera access in your browser, then tap Retry.",
        showRetry: true
      },
      notfound: {
        icon: "📷",
        title: "No camera found",
        sub: "Upload a photo or pick a sample document instead.",
        showRetry: false
      },
      unavailable: {
        icon: "📷",
        title: "Camera not available",
        sub: "Upload a photo or pick a sample document instead.",
        showRetry: false
      }
    };

    const { icon, title, sub, showRetry } = messages[type] || messages.unavailable;
    // No camera → flash is meaningless
    if (this.hasFlashBtnTarget) this.flashBtnTarget.style.visibility = "hidden";

    container.innerHTML = `
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
        <button class="btn btn-white btn-sm" data-action="click->document-capture#pickGallery">📁 Upload</button>
      </div>`;
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

  captureFrame() {
    this.autoCaptureTriggered = false;
    // Only fire the screen-flash animation when flash is enabled
    if (this._flashOn) {
      this.flashOverlayTarget.classList.add("dcap-flash--active");
      setTimeout(() => this.flashOverlayTarget.classList.remove("dcap-flash--active"), 180);
    }
    const video = this.videoTarget;
    if (video.srcObject && video.readyState >= 2) {
      const c = document.createElement("canvas");
      c.width = video.videoWidth || 640;
      c.height = video.videoHeight || 480;
      c.getContext("2d").drawImage(video, 0, 0);
      this.capturedImage = c;
    } else {
      this.capturedImage = this._buildSampleCanvas(0);
    }
    this._stopCamera();
    setTimeout(() => { this._showScreen(2); this._renderDetectCanvas(); }, 180);
  }

  useSample(e) {
    const idx = parseInt(e.currentTarget.dataset.idx || 0);
    this.capturedImage = this._buildSampleCanvas(idx);
    this._stopCamera();
    this._showScreen(2);
    this._renderDetectCanvas();
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
    this._flashOn = !this._flashOn;
    const btn = this.flashBtnTarget;
    btn.textContent = this._flashOn ? "🔦" : "⚡";
    btn.classList.toggle("dcap-icon-btn--active", this._flashOn);
    btn.setAttribute("aria-label", this._flashOn ? "Flash on" : "Flash off");
    // Apply torch to the live camera track if supported
    if (this._torchSupported && this._stream) {
      const track = this._stream.getVideoTracks()[0];
      try {
        await track.applyConstraints({ advanced: [{ torch: this._flashOn }] });
      } catch { /* torch constraint rejected — silently ignore */ }
    }
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

  // ── Stage 4: Review & Save ──────────────────────────────────────────────────
  _setupReviewScreen() {
    const src = this.enhancedCanvas || this.croppedCanvas;
    const rc = this.reviewCanvasTarget;
    if (src && rc) { rc.width = src.width; rc.height = src.height; rc.getContext("2d").drawImage(src, 0, 0); }
    const d = new Date();
    this.reviewTitleTarget.value = `Scan — ${d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })}`;
    this.reviewStatsTarget.innerHTML = src ? `
      <div class="dcap-stat"><div class="dcap-stat-label">Filter</div><div class="dcap-stat-value">${this.currentFilter}</div></div>
      <div class="dcap-stat"><div class="dcap-stat-label">Size</div><div class="dcap-stat-value">${src.width}×${src.height}px</div></div>
      <div class="dcap-stat"><div class="dcap-stat-label">PDF</div><div class="dcap-stat-value">Will be generated on save</div></div>` : "";
  }

  async save() {
    const btn = this.saveBtnTarget;
    btn.disabled = true;
    btn.textContent = "Saving…";
    const canvas = this.enhancedCanvas || this.croppedCanvas;
    if (!canvas) { btn.disabled = false; btn.textContent = "Save ✓"; return; }

    canvas.toBlob(async jpegBlob => {
      try {
        const formData = new FormData();
        formData.append("scanned_document[title]", this.reviewTitleTarget.value);
        formData.append("scanned_document[enhancement_filter]", this.currentFilter);
        formData.append("scanned_document[tags]", JSON.stringify(
          (this.reviewTagsTarget.value || "").split(",").map(t => t.trim()).filter(Boolean)
        ));
        formData.append("scanned_document[enhanced_image]", jpegBlob, "scan.jpg");

        // Generate PDF using jsPDF if available
        if (window.jspdf?.jsPDF) {
          btn.textContent = "Generating PDF…";
          const { jsPDF } = window.jspdf;
          const orientation = canvas.width > canvas.height ? "landscape" : "portrait";
          const pdf = new jsPDF({ orientation, unit: "px", format: [canvas.width, canvas.height], hotfixes: ["px_scaling"] });
          const imgData = canvas.toDataURL("image/jpeg", 0.92);
          pdf.addImage(imgData, "JPEG", 0, 0, canvas.width, canvas.height);
          const pdfBlob = pdf.output("blob");
          formData.append("scanned_document[pdf_document]", pdfBlob, "scan.pdf");
          btn.textContent = "Saving…";
        }

        const resp = await fetch(this.postUrlValue, {
          method: "POST",
          body: formData,
          headers: { "X-CSRF-Token": this.csrfValue, "X-Requested-With": "XMLHttpRequest" }
        });
        if (resp.ok || resp.redirected) {
          window.location.reload();
        } else {
          btn.disabled = false; btn.textContent = "Save ✓";
          alert("Save failed. Please try again.");
        }
      } catch {
        btn.disabled = false; btn.textContent = "Save ✓";
        alert("Network error. Please try again.");
      }
    }, "image/jpeg", 0.92);
  }

  // ── On-demand OCR ──────────────────────────────────────────────────────────
  async generateOcr(e) {
    const btn = e.currentTarget;
    const ocrUrl = btn.dataset.ocrUrl;
    if (!ocrUrl) return;
    btn.disabled = true;
    btn.textContent = "Processing…";
    try {
      const resp = await fetch(ocrUrl, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": this.csrfValue,
          "X-Requested-With": "XMLHttpRequest",
          "Accept": "application/json"
        }
      });
      if (resp.ok) {
        window.location.reload();
      } else {
        btn.disabled = false;
        btn.textContent = "🔤 Generate OCR";
        alert("OCR failed. Please try again.");
      }
    } catch {
      btn.disabled = false;
      btn.textContent = "🔤 Generate OCR";
      alert("Network error. Please try again.");
    }
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
      .then(() => { e.currentTarget.textContent = "✓ Copied"; setTimeout(() => { e.currentTarget.textContent = "📋 Copy"; }, 1500); })
      .catch(() => {});
  }
}
