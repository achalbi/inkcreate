import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = [
    "pendingLabel",
    "saveButton",
    "notebookSelect",
    "chapterSelect"
  ];

  static values = {
    placeholder: { type: String, default: "Choose a notebook and chapter" },
    notebooks: { type: Array, default: [] },
    inputId: String,
    displayLabelId: String
  };

  connect() {
    this.modalElement = this.element.closest(".modal");
    this.pendingChapterId = this.stringId(this.inputElement?.value);
    this.selectedNotebookId = this.notebookIdForChapter(this.pendingChapterId);
    this.boundResetPendingSelection = this.resetPendingSelection.bind(this);

    if (this.modalElement) {
      this.modalElement.addEventListener("show.bs.modal", this.boundResetPendingSelection);
    }

    this.syncFromInput();
  }

  disconnect() {
    if (this.modalElement) {
      this.modalElement.removeEventListener("show.bs.modal", this.boundResetPendingSelection);
    }
  }

  chooseNotebook(event) {
    event?.preventDefault();

    this.selectedNotebookId = this.hasNotebookSelectTarget ? this.stringId(this.notebookSelectTarget.value) : "";

    if (this.notebookIdForChapter(this.pendingChapterId) !== this.selectedNotebookId) {
      this.pendingChapterId = "";
    }

    this.syncSelects();
    this.renderPendingSelection();
    this.renderSaveState();
  }

  selectChapter(event) {
    event?.preventDefault();

    this.pendingChapterId = this.hasChapterSelectTarget ? this.stringId(this.chapterSelectTarget.value) : "";
    this.renderPendingSelection();
    this.renderSaveState();
  }

  save(event) {
    event?.preventDefault();
    if (!this.pendingChapterId) return;

    if (this.inputElement) {
      this.inputElement.value = this.pendingChapterId;
    }
    this.updateCommittedSelection();
    this.hideModal();
  }

  syncFromInput() {
    this.pendingChapterId = this.stringId(this.inputElement?.value);
    this.selectedNotebookId = this.notebookIdForChapter(this.pendingChapterId);
    this.updateCommittedSelection();
    this.syncSelects();
    this.renderPendingSelection();
    this.renderSaveState();
  }

  resetPendingSelection() {
    this.syncFromInput();
  }

  syncSelects() {
    if (this.hasNotebookSelectTarget) {
      this.notebookSelectTarget.value = this.selectedNotebookId || "";
    }

    this.updateChapterOptions();
  }

  updateChapterOptions() {
    const notebook = this.selectedNotebook();
    const visibleChapterDefinitions = notebook?.chapters || [];

    if (this.hasChapterSelectTarget) {
      this.chapterSelectTarget.innerHTML = "";

      const placeholderOption = document.createElement("option");
      placeholderOption.value = "";
      placeholderOption.textContent = "Choose a chapter";
      this.chapterSelectTarget.appendChild(placeholderOption);

      visibleChapterDefinitions.forEach((chapter) => {
        const option = document.createElement("option");
        option.value = this.stringId(chapter.chapterId);
        option.textContent = chapter.title;
        this.chapterSelectTarget.appendChild(option);
      });

      const hasPendingChapter = visibleChapterDefinitions.some((chapter) => this.stringId(chapter.chapterId) === this.pendingChapterId);
      this.chapterSelectTarget.value = hasPendingChapter ? this.pendingChapterId : "";
      this.chapterSelectTarget.disabled = !notebook || visibleChapterDefinitions.length === 0;
    }
  }

  updateCommittedSelection() {
    const selectedChapter = this.chapterDefinitionFor(this.inputElement?.value);
    const selectedLabel = selectedChapter?.label || this.placeholderValue;

    if (this.displayLabelElement) {
      this.displayLabelElement.textContent = selectedLabel;
    }
  }

  renderPendingSelection() {
    const pendingChapter = this.chapterDefinitionFor(this.pendingChapterId);
    const pendingLabel = pendingChapter?.label || this.placeholderValue;

    this.pendingLabelTargets.forEach((label) => {
      label.textContent = pendingLabel;
    });
  }

  renderSaveState() {
    if (!this.hasSaveButtonTarget) return;

    const canSave = this.pendingChapterId.length > 0;
    this.saveButtonTarget.disabled = !canSave;
    this.saveButtonTarget.classList.toggle("disabled", !canSave);
  }

  selectedChapterOption(chapterId) {
    return this.chapterDefinitionFor(chapterId);
  }

  chapterDefinitionFor(chapterId) {
    const normalizedChapterId = this.stringId(chapterId);
    if (!normalizedChapterId) return null;

    for (const notebook of this.notebooksValue) {
      const chapter = (notebook.chapters || []).find((candidate) => this.stringId(candidate.chapterId) === normalizedChapterId);
      if (chapter) {
        return chapter;
      }
    }

    return null;
  }

  notebookIdForChapter(chapterId) {
    const chapter = this.chapterDefinitionFor(chapterId);
    return this.stringId(chapter?.notebookId);
  }

  selectedNotebook() {
    if (!this.selectedNotebookId) return null;

    return this.notebooksValue.find((notebook) => this.stringId(notebook.notebookId) === this.selectedNotebookId) || null;
  }

  stringId(value) {
    return value == null ? "" : String(value);
  }

  hideModal() {
    if (!this.modalElement) return;

    const ModalClass = window.bootstrap?.Modal;
    if (!ModalClass) return;

    const modal = ModalClass.getInstance(this.modalElement) || ModalClass.getOrCreateInstance(this.modalElement);
    modal.hide();
  }

  get inputElement() {
    if (!this.hasInputIdValue) return null;
    return document.getElementById(this.inputIdValue);
  }

  get displayLabelElement() {
    if (!this.hasDisplayLabelIdValue) return null;
    return document.getElementById(this.displayLabelIdValue);
  }
}
