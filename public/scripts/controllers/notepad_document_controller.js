import { Controller } from "/scripts/vendor/stimulus.js";

/**
 * NotepadDocumentController
 *
 * Handles format export (Markdown + plain-text / ASCII doc) for the
 * flowing notepad document view.
 *
 * Targets
 *   body            – the .notepad-doc__body element
 *   notesBlock      – the rich-text block
 *   photosBlock     – the photo strip wrapper
 *   voiceBlock      – the voice-note list
 *   todosBlock      – the todo-list-items wrapper
 *   scansBlock      – the sdoc-list wrapper
 *   formatOutput    – <textarea> inside the export modal
 *   formatModalTitle – <span> in the modal header
 *   formatHint      – hint text row inside modal
 *
 * Values
 *   title           – document title string (from data attr)
 *   date            – document date string (from data attr)
 *   formatModalId   – id of the Bootstrap modal element
 */
export default class extends Controller {
  static targets = [
    "body",
    "notesBlock",
    "photosBlock",
    "voiceBlock",
    "todosBlock",
    "scansBlock",
    "formatOutput",
    "formatModalTitle",
    "formatHint",
  ];

  static values = {
    title: String,
    date: String,
    formatModalId: String,
  };

  // ── Public actions ──────────────────────────────────────────────────

  exportMarkdown(event) {
    event?.preventDefault();
    const text = this.buildMarkdown();
    this.openModal("Markdown export", text);
  }

  exportAscii(event) {
    event?.preventDefault();
    const text = this.buildAscii();
    this.openModal("Plain text / ASCII doc", text);
  }

  copyFormat(event) {
    event?.preventDefault();
    if (!this.hasFormatOutputTarget) return;

    const text = this.formatOutputTarget.value;
    if (!text) return;

    if (navigator.clipboard?.writeText) {
      navigator.clipboard.writeText(text).then(() => {
        this.flashCopied();
      }).catch(() => {
        this.selectAll();
      });
    } else {
      this.selectAll();
    }
  }

  // ── Markdown builder ────────────────────────────────────────────────

  buildMarkdown() {
    const lines = [];
    const title = this.titleValue || this.docTitle();
    const date = this.dateValue || "";

    lines.push(`# ${title}`);
    if (date) lines.push(`*${date}*`);
    lines.push("");

    // Notes
    const notes = this.plainNotes();
    if (notes) {
      lines.push(notes);
      lines.push("");
    }

    // Photos
    const photoCount = this.photoCount();
    if (photoCount > 0) {
      lines.push("## Photos");
      lines.push(`*${photoCount} photo${photoCount !== 1 ? "s" : ""} attached*`);
      lines.push("");
    }

    // Voice notes
    const voiceItems = this.voiceNoteItems();
    if (voiceItems.length > 0) {
      lines.push("## Voice notes");
      voiceItems.forEach((v) => lines.push(`- ${v}`));
      lines.push("");
    }

    // To-dos
    const todos = this.todoItems();
    if (todos.length > 0) {
      lines.push("## To-do list");
      todos.forEach(({ text, done }) => {
        lines.push(`- [${done ? "x" : " "}] ${text}`);
      });
      lines.push("");
    }

    // Scanned docs
    const scans = this.scanItems();
    if (scans.length > 0) {
      lines.push("## Scanned documents");
      scans.forEach((s) => lines.push(`- ${s}`));
      lines.push("");
    }

    return lines.join("\n").trimEnd();
  }

  // ── ASCII / plain-text builder ──────────────────────────────────────

  buildAscii() {
    const lines = [];
    const title = this.titleValue || this.docTitle();
    const date = this.dateValue || "";
    const hr = (label) => {
      const filled = `── ${label} `;
      return filled.padEnd(52, "─");
    };

    // Header
    lines.push(title.toUpperCase());
    lines.push("═".repeat(Math.min(title.length, 52)));
    if (date) lines.push(`Date: ${date}`);
    lines.push("");

    // Notes
    const notes = this.plainNotes();
    if (notes) {
      lines.push(notes);
      lines.push("");
    }

    // Photos
    const photoCount = this.photoCount();
    if (photoCount > 0) {
      lines.push(hr("PHOTOS"));
      lines.push(`${photoCount} photo${photoCount !== 1 ? "s" : ""} attached`);
      lines.push("");
    }

    // Voice notes
    const voiceItems = this.voiceNoteItems();
    if (voiceItems.length > 0) {
      lines.push(hr("VOICE NOTES"));
      voiceItems.forEach((v) => lines.push(`  • ${v}`));
      lines.push("");
    }

    // To-dos
    const todos = this.todoItems();
    if (todos.length > 0) {
      lines.push(hr("TO-DO LIST"));
      todos.forEach(({ text, done }) => {
        lines.push(`  [${done ? "✓" : " "}] ${text}`);
      });
      lines.push("");
    }

    // Scanned docs
    const scans = this.scanItems();
    if (scans.length > 0) {
      lines.push(hr("SCANNED DOCUMENTS"));
      scans.forEach((s) => lines.push(`  • ${s}`));
      lines.push("");
    }

    return lines.join("\n").trimEnd();
  }

  // ── DOM readers ─────────────────────────────────────────────────────

  docTitle() {
    const h1 = this.element.querySelector(".notepad-doc__title");
    return h1 ? h1.textContent.trim() : "Untitled";
  }

  plainNotes() {
    if (!this.hasNotesBlockTarget) return "";
    // Collect text content, preserving list items and block structure
    const el = this.notesBlockTarget;
    return this.extractText(el).trim();
  }

  extractText(el) {
    let text = "";
    for (const node of el.childNodes) {
      if (node.nodeType === Node.TEXT_NODE) {
        text += node.textContent;
      } else if (node.nodeType === Node.ELEMENT_NODE) {
        const tag = node.tagName.toLowerCase();
        if (tag === "br") {
          text += "\n";
        } else if (["p", "div", "h1", "h2", "h3", "h4", "blockquote"].includes(tag)) {
          const inner = this.extractText(node).trim();
          if (inner) text += inner + "\n";
        } else if (tag === "li") {
          text += "• " + this.extractText(node).trim() + "\n";
        } else if (tag === "ul" || tag === "ol") {
          text += this.extractText(node);
        } else {
          text += this.extractText(node);
        }
      }
    }
    return text;
  }

  photoCount() {
    if (!this.hasPhotosBlockTarget) return 0;
    return this.photosBlockTarget.querySelectorAll(".notepad-doc__photo-item").length;
  }

  voiceNoteItems() {
    if (!this.hasVoiceBlockTarget) return [];
    const items = [];
    this.voiceBlockTarget.querySelectorAll(".voice-note-list-item, [class*='voice-note']").forEach((el) => {
      // Try to extract duration or title from the voice note item
      const duration = el.querySelector("[class*='duration'], [class*='timer'], time");
      const label = el.querySelector("[class*='title'], [class*='label'], [class*='name']");
      let text = label ? label.textContent.trim() : "";
      const dur = duration ? duration.textContent.trim() : "";
      if (!text) {
        // Fallback: grab first meaningful text node
        text = el.textContent.trim().split("\n")[0].trim().substring(0, 60);
      }
      if (text || dur) items.push([text, dur].filter(Boolean).join(" — "));
    });
    // If no structured items found, just count them
    if (items.length === 0) {
      const count = this.voiceBlockTarget.children.length;
      if (count > 0) {
        for (let i = 1; i <= count; i++) items.push(`Voice note ${i}`);
      }
    }
    return items;
  }

  todoItems() {
    if (!this.hasTodosBlockTarget) return [];
    const items = [];
    this.todosBlockTarget.querySelectorAll(".todo-list-item").forEach((el) => {
      const done = el.classList.contains("is-completed");
      const input = el.querySelector(".todo-list-item__input, textarea[name='todo_item[content]']");
      const text = input ? (input.value || input.textContent).trim() : el.textContent.trim().substring(0, 80);
      if (text) items.push({ text, done });
    });
    return items;
  }

  scanItems() {
    if (!this.hasScansBlockTarget) return [];
    const items = [];
    this.scansBlockTarget.querySelectorAll(".sdoc-card").forEach((el) => {
      const titleEl = el.querySelector(".sdoc-title, .sdoc-title-button");
      const dateEl = el.querySelector(".sdoc-engine-label, .sdoc-meta");
      const title = titleEl ? titleEl.textContent.trim() : "Untitled scan";
      const meta = dateEl ? dateEl.textContent.trim() : "";
      items.push([title, meta].filter(Boolean).join(" · "));
    });
    return items;
  }

  // ── Modal helpers ───────────────────────────────────────────────────

  openModal(formatLabel, text) {
    if (this.hasFormatModalTitleTarget) {
      this.formatModalTitleTarget.textContent = formatLabel;
    }
    if (this.hasFormatOutputTarget) {
      this.formatOutputTarget.value = text;
    }

    const modalEl = document.getElementById(this.formatModalIdValue);
    if (!modalEl) return;

    const ModalClass = window.bootstrap?.Modal;
    if (ModalClass) {
      ModalClass.getOrCreateInstance(modalEl).show();
    } else {
      modalEl.classList.add("show");
      modalEl.style.display = "block";
    }
  }

  selectAll() {
    if (!this.hasFormatOutputTarget) return;
    this.formatOutputTarget.select();
  }

  flashCopied() {
    if (!this.hasFormatHintTarget) return;
    const original = this.formatHintTarget.textContent;
    this.formatHintTarget.textContent = "Copied to clipboard!";
    window.setTimeout(() => {
      this.formatHintTarget.textContent = original;
    }, 2200);
  }
}
