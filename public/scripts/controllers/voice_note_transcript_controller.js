import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = [
    "copyButton",
    "extractButton",
    "panel",
    "shareButton",
    "status",
    "text",
    "toggleButton"
  ];

  static values = {
    audioUrl: String,
    submitUrl: String,
    title: String
  };

  connect() {
    this.panelOpen = false;
    this.isExtracting = false;
    this.extractButtonMarkup = this.hasExtractButtonTarget ? this.extractButtonTarget.innerHTML : "";
    this.render();
  }

  toggle() {
    if (!this.hasTranscript()) {
      return;
    }

    this.panelOpen = !this.panelOpen;
    this.render();
  }

  async extract() {
    if (this.isExtracting || !this.hasExtractButtonTarget) {
      return;
    }

    if (!this.isNativeSpeechRecognitionAvailable()) {
      this.setStatus("Speech extraction runs in the Android app.", "info");
      this.render();
      return;
    }

    this.isExtracting = true;
    this.setBusyState(true);
    this.setStatus("Extracting speech to text…", "info");
    this.render();

    try {
      const plugin = this.nativeSpeechRecognitionPlugin();
      const runner = plugin?.transcribeAudio || plugin?.startTranscription || plugin?.extractSpeech;

      if (typeof runner !== "function") {
        throw new Error("Speech recognition plugin is unavailable.");
      }

      const result = await runner.call(plugin, {
        audioUrl: this.absoluteAudioUrl(),
        locale: this.detectLocale(),
        preferredMode: "basic"
      });

      const transcript = (result?.text || "").trim();

      if (!transcript) {
        throw new Error("No speech was detected in this voice note.");
      }

      const savedTranscript = await this.persistTranscript(transcript);

      this.textTarget.value = savedTranscript;
      this.panelOpen = true;
      this.setStatus("Transcript ready.", "success");
      this.render();
    } catch (error) {
      if (error?.name === "AbortError") {
        this.clearStatus();
      } else {
        this.setStatus(error?.message || "Speech extraction failed. Please try again.", "error");
      }
    } finally {
      this.isExtracting = false;
      this.setBusyState(false);
      this.render();
    }
  }

  async copy() {
    const transcript = this.transcriptText();
    if (!transcript) {
      return;
    }

    try {
      await this.copyToClipboard(transcript);
      this.setStatus("Transcript copied.", "success");
    } catch (_error) {
      this.setStatus("Could not copy the transcript on this device.", "error");
    }
  }

  async share() {
    const transcript = this.transcriptText();
    if (!transcript) {
      return;
    }

    try {
      if (navigator.share) {
        await navigator.share({
          title: this.titleValue || "Voice note transcript",
          text: transcript
        });
        this.setStatus("Transcript shared.", "success");
        return;
      }

      await this.copyToClipboard(transcript);
      this.setStatus("Share is unavailable here, so the transcript was copied instead.", "info");
    } catch (error) {
      if (error?.name === "AbortError") {
        return;
      }

      this.setStatus("Could not share the transcript on this device.", "error");
    }
  }

  render() {
    const hasTranscript = this.hasTranscript();
    const nativeAvailable = this.isNativeSpeechRecognitionAvailable();

    if (this.hasPanelTarget) {
      this.panelTarget.hidden = !(hasTranscript && this.panelOpen);
    }

    if (this.hasToggleButtonTarget) {
      this.toggleButtonTarget.hidden = !hasTranscript;
      this.toggleButtonTarget.querySelector("span").textContent = this.panelOpen ? "Hide text" : "View text";
    }

    if (this.hasCopyButtonTarget) {
      this.copyButtonTarget.hidden = !hasTranscript;
    }

    if (this.hasShareButtonTarget) {
      this.shareButtonTarget.hidden = !hasTranscript;
    }

    if (this.hasExtractButtonTarget) {
      const shouldHideExtractButton = !nativeAvailable && hasTranscript;
      this.extractButtonTarget.hidden = shouldHideExtractButton;
      this.extractButtonTarget.disabled = this.isExtracting;
    }

    if (!nativeAvailable && !hasTranscript && !this.statusVisible()) {
      this.setStatus("Speech extraction runs in the Android app.", "info");
    }
  }

  async persistTranscript(transcript) {
    const response = await fetch(this.submitUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken(),
        "X-Requested-With": "XMLHttpRequest"
      },
      body: JSON.stringify({
        transcript_result: {
          text: transcript
        }
      })
    });

    const payload = await response.json().catch(() => null);

    if (!response.ok) {
      throw new Error(payload?.error || "Could not save the transcript.");
    }

    const savedTranscript = (payload?.transcript || transcript).trim();
    if (!savedTranscript) {
      throw new Error("The transcript could not be saved.");
    }

    return savedTranscript;
  }

  hasTranscript() {
    return this.transcriptText().length > 0;
  }

  transcriptText() {
    return this.hasTextTarget ? this.textTarget.value.trim() : "";
  }

  setBusyState(isBusy) {
    if (!this.hasExtractButtonTarget) {
      return;
    }

    if (isBusy) {
      this.extractButtonTarget.innerHTML = `
        <i class="ti ti-loader-2 voice-note-transcript__spinner" aria-hidden="true"></i>
        <span>Extracting…</span>
      `;
      this.extractButtonTarget.setAttribute("aria-busy", "true");
      return;
    }

    this.extractButtonTarget.innerHTML = this.extractButtonMarkup;
    this.extractButtonTarget.removeAttribute("aria-busy");
  }

  setStatus(message, tone = "info") {
    if (!this.hasStatusTarget) {
      return;
    }

    const text = `${message || ""}`.trim();
    if (!text) {
      this.clearStatus();
      return;
    }

    this.statusTarget.hidden = false;
    this.statusTarget.dataset.tone = tone;
    this.statusTarget.textContent = text;
  }

  clearStatus() {
    if (!this.hasStatusTarget) {
      return;
    }

    this.statusTarget.hidden = true;
    this.statusTarget.textContent = "";
    delete this.statusTarget.dataset.tone;
  }

  statusVisible() {
    return this.hasStatusTarget && !this.statusTarget.hidden && this.statusTarget.textContent.trim().length > 0;
  }

  absoluteAudioUrl() {
    return new URL(this.audioUrlValue, window.location.href).toString();
  }

  detectLocale() {
    return navigator.languages?.[0] || navigator.language || document.documentElement.lang || "en-US";
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || "";
  }

  nativeSpeechRecognitionPlugin() {
    return window.InkcreateSpeechRecognition
      || window.Capacitor?.Plugins?.InkcreateSpeechRecognition
      || window.Capacitor?.Plugins?.NativeSpeechRecognition
      || null;
  }

  isNativeSpeechRecognitionAvailable() {
    return this.isNativeAndroidApp() && Boolean(this.nativeSpeechRecognitionPlugin());
  }

  isNativeAndroidApp() {
    return this.capacitorPlatform() === "android" && this.isNativeCapacitorApp();
  }

  capacitorPlatform() {
    const capacitor = window.Capacitor;
    if (!capacitor || typeof capacitor.getPlatform !== "function") {
      return null;
    }

    return capacitor.getPlatform();
  }

  isNativeCapacitorApp() {
    const capacitor = window.Capacitor;
    if (!capacitor) {
      return false;
    }

    if (typeof capacitor.isNativePlatform === "function") {
      return capacitor.isNativePlatform();
    }

    const platform = this.capacitorPlatform();
    return platform === "android" || platform === "ios";
  }

  async copyToClipboard(text) {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return;
    }

    const element = document.createElement("textarea");
    element.value = text;
    element.setAttribute("readonly", "");
    element.style.position = "absolute";
    element.style.left = "-9999px";
    document.body.appendChild(element);
    element.select();

    const copied = document.execCommand("copy");
    document.body.removeChild(element);

    if (!copied) {
      throw new Error("Clipboard unavailable");
    }
  }
}
