import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = [
    "pendingLabel",
    "saveButton",
    "notebookMenu",
    "chapterMenu",
    "notebookButtonLabel",
    "chapterButtonLabel",
    "chapterButton"
  ];

  static values = {
    placeholder: { type: String, default: "Choose a notebook and chapter" },
    notebooks: { type: Array, default: [] },
    inputId: String,
    displayLabelId: String
  };

  connect() {
    this.modalElement = this.element.closest(".modal");
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

    this.selectedNotebookId = this.stringId(event?.currentTarget?.dataset?.notebookId);

    if (this.notebookIdForChapter(this.pendingChapterId) !== this.selectedNotebookId) {
      this.pendingChapterId = "";
    }

    this.render();
    this.hideDropdownFor(event?.currentTarget);
  }

  selectChapter(event) {
    event?.preventDefault();

    this.selectedNotebookId = this.stringId(event?.currentTarget?.dataset?.notebookId) || this.selectedNotebookId;
    this.pendingChapterId = this.stringId(event?.currentTarget?.dataset?.chapterId);
    this.render();
    this.hideDropdownFor(event?.currentTarget);
  }

  save(event) {
    event?.preventDefault();
    if (!this.pendingChapterId) return;

    this.persistSelection();
    this.hideModal();
  }

  resetPendingSelection() {
    this.syncFromInput();
  }

  commitSelection() {
    if (!this.pendingChapterId) return;

    this.persistSelection();
  }

  syncFromInput() {
    this.pendingChapterId = this.stringId(this.inputElement?.value);
    this.selectedNotebookId = this.notebookIdForChapter(this.pendingChapterId);
    this.updateCommittedSelection();
    this.render();
  }

  render() {
    this.renderNotebookButton();
    this.renderNotebookMenu();
    this.renderChapterButton();
    this.renderChapterMenu();
    this.renderPendingSelection();
    this.renderSaveState();
  }

  renderNotebookButton() {
    if (!this.hasNotebookButtonLabelTarget) return;

    const notebook = this.selectedNotebook();
    this.notebookButtonLabelTarget.textContent = this.labelFor(notebook?.title, "Choose a notebook");
  }

  renderNotebookMenu() {
    if (!this.hasNotebookMenuTarget) return;

    this.notebookMenuTarget.replaceChildren(
      ...this.notebooksValue.map((notebook) => this.buildNotebookItem(notebook))
    );
  }

  renderChapterButton() {
    if (!this.hasChapterButtonTarget || !this.hasChapterButtonLabelTarget) return;

    const notebook = this.selectedNotebook();
    const selectedChapter = this.chapterDefinitionFor(this.pendingChapterId);
    const chapters = notebook?.chapters || [];
    const canChooseChapter = !!notebook && chapters.length > 0;

    this.chapterButtonTarget.disabled = !canChooseChapter;
    this.chapterButtonTarget.classList.toggle("disabled", !canChooseChapter);

    if (selectedChapter && this.notebookIdForChapter(selectedChapter.chapterId) === this.selectedNotebookId) {
      this.chapterButtonLabelTarget.textContent = this.labelFor(selectedChapter.title, "Choose a chapter");
      return;
    }

    this.chapterButtonLabelTarget.textContent = canChooseChapter ? "Choose a chapter" : "Choose a notebook first";
  }

  renderChapterMenu() {
    if (!this.hasChapterMenuTarget) return;

    const notebook = this.selectedNotebook();
    const chapters = notebook?.chapters || [];

    if (!notebook) {
      this.chapterMenuTarget.replaceChildren(
        this.buildDisabledItem("Choose a notebook first", "Chapter options appear after notebook selection.")
      );
      return;
    }

    if (chapters.length === 0) {
      this.chapterMenuTarget.replaceChildren(
        this.buildDisabledItem("No chapters yet", "Create a chapter in this notebook before moving the page.")
      );
      return;
    }

    this.chapterMenuTarget.replaceChildren(
      ...chapters.map((chapter) => this.buildChapterItem(notebook, chapter))
    );
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

  buildNotebookItem(notebook) {
    const notebookId = this.stringId(notebook.notebookId);
    const isSelected = notebookId === this.selectedNotebookId;

    return this.buildDropdownItem({
      title: this.labelFor(notebook.title, "Untitled notebook"),
      meta: this.countLabel((notebook.chapters || []).length, "chapter"),
      dataset: { notebookId },
      action: "chooseNotebook",
      isSelected
    });
  }

  buildChapterItem(notebook, chapter) {
    const notebookId = this.stringId(notebook.notebookId);
    const chapterId = this.stringId(chapter.chapterId);
    const isSelected = chapterId === this.pendingChapterId;

    return this.buildDropdownItem({
      title: this.labelFor(chapter.title, "Untitled chapter"),
      meta: this.labelFor(notebook.title, "Notebook"),
      dataset: { notebookId, chapterId },
      action: "selectChapter",
      isSelected
    });
  }

  buildDisabledItem(title, meta) {
    const button = this.buildDropdownItem({
      title,
      meta,
      dataset: {},
      action: null,
      isSelected: false
    });

    button.disabled = true;
    button.classList.add("disabled");
    return button;
  }

  buildDropdownItem({ title, meta, dataset, action, isSelected }) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "dropdown-item notepad-entry-move-modal__dropdown-item";

    if (action) {
      button.dataset.action = `click->move-destination#${action}`;
    }

    Object.entries(dataset).forEach(([key, value]) => {
      button.dataset[key] = value;
    });

    if (isSelected) {
      button.classList.add("active");
      button.setAttribute("aria-current", "true");
    }

    const titleElement = document.createElement("span");
    titleElement.className = "notepad-entry-move-modal__dropdown-item-title";
    titleElement.textContent = title;

    const metaElement = document.createElement("span");
    metaElement.className = "notepad-entry-move-modal__dropdown-item-meta";
    metaElement.textContent = meta;

    button.append(titleElement, metaElement);
    return button;
  }

  updateCommittedSelection() {
    const selectedChapter = this.chapterDefinitionFor(this.inputElement?.value);
    const selectedLabel = selectedChapter?.label || this.placeholderValue;

    if (this.displayLabelElement) {
      this.displayLabelElement.textContent = selectedLabel;
    }
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

  countLabel(count, noun) {
    return `${count} ${noun}${count === 1 ? "" : "s"}`;
  }

  labelFor(value, fallback) {
    return String(value || "").trim() || fallback;
  }

  stringId(value) {
    return value == null ? "" : String(value);
  }

  hideDropdownFor(source) {
    const toggle = source?.closest(".dropdown")?.querySelector("[data-bs-toggle='dropdown']");
    if (!(toggle instanceof HTMLElement)) return;

    const DropdownClass = window.bootstrap?.Dropdown;
    if (!DropdownClass) return;

    const dropdown = DropdownClass.getInstance(toggle) || DropdownClass.getOrCreateInstance(toggle);
    dropdown.hide();
  }

  hideModal() {
    if (!this.modalElement) return;

    const ModalClass = window.bootstrap?.Modal;
    if (!ModalClass) return;

    const modal = ModalClass.getInstance(this.modalElement) || ModalClass.getOrCreateInstance(this.modalElement);
    modal.hide();
  }

  persistSelection() {
    if (this.inputElement) {
      this.inputElement.value = this.pendingChapterId;
    }

    this.updateCommittedSelection();
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
