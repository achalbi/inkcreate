import { Controller } from "/scripts/vendor/stimulus.js";
import WaveSurfer from "/scripts/vendor/wavesurfer.js";

const SEEK_STEP_SECONDS = 5;
const WAVEFORM_OPTIONS = {
  barAlign: "bottom",
  barGap: 2,
  barRadius: 999,
  barWidth: 3,
  cursorWidth: 0,
  dragToSeek: false,
  height: 28,
  interact: false,
  normalize: true,
  progressColor: "#e66239",
  waveColor: "rgba(165, 150, 136, 0.52)"
};

export default class extends Controller {
  static targets = [
    "durationLabel",
    "elapsedLabel",
    "playButton",
    "playIcon",
    "timeline",
    "waveform"
  ];

  static values = {
    duration: { type: Number, default: 0 },
    url: String
  };

  connect() {
    this.element.voiceNotePlayerController = this;
    this.waveSurferSubscriptions = [];
    this.createWaveform();
    this.renderState();
  }

  disconnect() {
    delete this.element.voiceNotePlayerController;
    this.destroyWaveform();
  }

  async toggle() {
    if (!this.waveSurfer) {
      return;
    }

    if (!this.isPlaying()) {
      this.pauseOtherPlayers();
    }

    try {
      await this.waveSurfer.playPause();
    } catch (_error) {
      // Keep the player stable if playback is blocked.
    }

    this.renderState();
  }

  seek(event) {
    const duration = this.duration();
    if (!duration || !this.waveSurfer) {
      return;
    }

    const rect = this.timelineTarget.getBoundingClientRect();
    const ratio = this.clamp((event.clientX - rect.left) / rect.width, 0, 1);
    this.waveSurfer.setTime(duration * ratio);
    this.renderState();
  }

  seekWithKeyboard(event) {
    const duration = this.duration();
    if (!duration || !this.waveSurfer) {
      return;
    }

    let nextTime = null;

    switch (event.key) {
      case "ArrowLeft":
      case "ArrowDown":
        nextTime = this.currentTime() - SEEK_STEP_SECONDS;
        break;
      case "ArrowRight":
      case "ArrowUp":
        nextTime = this.currentTime() + SEEK_STEP_SECONDS;
        break;
      case "Home":
        nextTime = 0;
        break;
      case "End":
        nextTime = duration;
        break;
      default:
        return;
    }

    event.preventDefault();
    this.waveSurfer.setTime(this.clamp(nextTime, 0, duration));
    this.renderState();
  }

  pause() {
    if (this.waveSurfer?.isPlaying()) {
      this.waveSurfer.pause();
    }
  }

  createWaveform() {
    if (!this.hasWaveformTarget || !this.urlValue) {
      return;
    }

    this.waveSurfer = WaveSurfer.create({
      ...WAVEFORM_OPTIONS,
      container: this.waveformTarget,
      url: this.urlValue
    });

    this.waveSurferSubscriptions = [
      this.waveSurfer.on("ready", (duration) => {
        if ((!this.durationValue || this.durationValue <= 0) && Number.isFinite(duration)) {
          this.durationValue = duration;
        }

        this.renderState();
      }),
      this.waveSurfer.on("timeupdate", () => this.renderState()),
      this.waveSurfer.on("play", () => this.renderState()),
      this.waveSurfer.on("pause", () => this.renderState()),
      this.waveSurfer.on("finish", () => this.handleEnded()),
      this.waveSurfer.on("error", () => this.renderState())
    ];
  }

  destroyWaveform() {
    this.pause();
    this.waveSurferSubscriptions.forEach((unsubscribe) => unsubscribe());
    this.waveSurferSubscriptions = [];

    if (this.waveSurfer) {
      this.waveSurfer.destroy();
      this.waveSurfer = null;
    }
  }

  handleEnded() {
    if (this.waveSurfer) {
      this.waveSurfer.setTime(0);
    }

    this.renderState();
  }

  renderState() {
    const duration = this.duration();
    const currentTime = this.clamp(this.currentTime(), 0, duration || this.currentTime());
    const ratio = duration > 0 ? currentTime / duration : 0;

    this.timelineTarget.setAttribute("aria-valuenow", String(Math.round(ratio * 100)));
    this.timelineTarget.setAttribute("aria-valuetext", `${this.formatTime(currentTime)} of ${this.formatTime(duration)}`);
    this.elapsedLabelTarget.textContent = this.formatTime(currentTime);
    this.durationLabelTarget.textContent = this.formatTime(duration);
    this.playButtonTarget.setAttribute("aria-label", this.isPlaying() ? "Pause voice note" : "Play voice note");
    this.playIconTarget.className = this.isPlaying() ? "ti ti-player-pause" : "ti ti-player-play";
  }

  pauseOtherPlayers() {
    document.querySelectorAll("[data-controller~='voice-note-player']").forEach((element) => {
      if (element === this.element) {
        return;
      }

      element.voiceNotePlayerController?.pause();
    });
  }

  duration() {
    const waveSurferDuration = this.waveSurfer?.getDuration?.();

    if (Number.isFinite(waveSurferDuration) && waveSurferDuration > 0) {
      return waveSurferDuration;
    }

    return this.durationValue;
  }

  currentTime() {
    const waveSurferTime = this.waveSurfer?.getCurrentTime?.();
    return Number.isFinite(waveSurferTime) ? waveSurferTime : 0;
  }

  isPlaying() {
    return Boolean(this.waveSurfer?.isPlaying?.());
  }

  clamp(value, min, max) {
    return Math.min(Math.max(value, min), max);
  }

  formatTime(totalSeconds) {
    const seconds = Math.max(Math.floor(totalSeconds || 0), 0);
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const remainingSeconds = seconds % 60;

    if (hours > 0) {
      return `${hours}:${String(minutes).padStart(2, "0")}:${String(remainingSeconds).padStart(2, "0")}`;
    }

    return `${String(minutes).padStart(2, "0")}:${String(remainingSeconds).padStart(2, "0")}`;
  }
}
