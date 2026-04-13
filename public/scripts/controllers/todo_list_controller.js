import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = [
    "draftInput",
    "draftItems",
    "draftFields",
    "enabledField",
    "hideCompletedField",
    "items",
    "filterButton",
    "filterEmpty",
    "deleteModal",
    "deleteForm",
    "deleteMessage"
  ];

  static values = {
    mode: { type: String, default: "persisted" },
    draftFieldName: { type: String, default: "page[todo_item_contents][]" },
    filter: { type: String, default: "all" },
    storageKey: String
  };

  connect() {
    this.pendingDraftItems = [];
    this.draggedElement = null;
    this.defaultDeleteMessage = this.hasDeleteMessageTarget
      ? this.deleteMessageTarget.textContent.trim()
      : "This item will be removed from the list.";
    this.boundResetDeleteConfirmation = this.resetDeleteConfirmation.bind(this);
    this.restorePersistedFilter();
    this.renderDraftItems();
    this.renderPersistedState();
    this.resizeAllTextareas();

    if (this.hasDeleteModalTarget) {
      this.deleteModalTarget.addEventListener("hidden.bs.modal", this.boundResetDeleteConfirmation);
    }
  }

  disconnect() {
    if (this.hasDeleteModalTarget) {
      this.deleteModalTarget.removeEventListener("hidden.bs.modal", this.boundResetDeleteConfirmation);
    }
  }

  addDraftItem() {
    if (!this.hasDraftInputTarget) {
      return;
    }

    const value = this.draftInputTarget.value.trim();
    if (!value) {
      return;
    }

    this.pendingDraftItems.push(value);
    if (this.hasEnabledFieldTarget) {
      this.enabledFieldTarget.value = "true";
    }

    this.draftInputTarget.value = "";
    this.resizeElement(this.draftInputTarget);
    this.renderDraftItems();
  }

  removeDraftItem(event) {
    const index = Number.parseInt(event.currentTarget.dataset.index || "", 10);
    if (!Number.isFinite(index)) {
      return;
    }

    this.pendingDraftItems.splice(index, 1);
    this.renderDraftItems();
  }

  setFilter(event) {
    if (this.modeValue !== "persisted") {
      return;
    }

    this.filterValue = event.params.filter || event.currentTarget.dataset.filter || "all";
    this.persistFilter();
    this.renderPersistedState();
  }

  async submit(event) {
    if (this.modeValue !== "persisted") {
      return;
    }

    event.preventDefault();
    await this.submitForm(event.currentTarget);
  }

  autosave(event) {
    if (this.modeValue !== "persisted") {
      return;
    }

    const input = event.currentTarget;
    window.setTimeout(() => {
      if (!(input instanceof HTMLInputElement || input instanceof HTMLTextAreaElement) || !input.isConnected) {
        return;
      }

      const form = input.closest("form");
      if (!(form instanceof HTMLFormElement)) {
        return;
      }

      const item = input.closest(".todo-list-item");
      const nextFocus = document.activeElement;

      if (
        item instanceof HTMLElement &&
        nextFocus instanceof HTMLElement &&
        item.contains(nextFocus) &&
        !form.contains(nextFocus)
      ) {
        return;
      }

      this.submitEditedItem(form, input);
    }, 0);
  }

  handleEditKeydown(event) {
    if (this.modeValue !== "persisted") {
      return;
    }

    const input = event.currentTarget;
    const form = input?.closest("form");
    if (!(input instanceof HTMLInputElement || input instanceof HTMLTextAreaElement) || !(form instanceof HTMLFormElement)) {
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      input.value = input.dataset.initialValue || input.value;
      this.resizeElement(input);
      input.blur();
    }
  }

  resizeTextarea(event) {
    const input = event?.currentTarget;
    if (!(input instanceof HTMLTextAreaElement)) {
      return;
    }

    this.resizeElement(input);
  }

  confirmDelete(event) {
    event.preventDefault();

    const trigger = event.currentTarget;
    const deleteUrl = trigger?.dataset?.todoListDeleteUrl;
    if (!deleteUrl || !this.hasDeleteModalTarget || !this.hasDeleteFormTarget) {
      return;
    }

    const content = (trigger.dataset.todoListItemContent || "This item").trim();
    this.deleteFormTarget.action = deleteUrl;

    if (this.hasDeleteMessageTarget) {
      this.deleteMessageTarget.textContent = `"${content}" will be removed from this list.`;
    }

    this.showDeleteModal();
  }

  async submitForm(form) {
    if (!(form instanceof HTMLFormElement)) {
      return;
    }

    const formData = new FormData(form);

    try {
      const response = await fetch(form.action, {
        method: form.method.toUpperCase(),
        body: formData,
        credentials: "same-origin",
        headers: {
          "X-CSRF-Token": this.csrfToken(),
          "Accept": "application/json"
        }
      });

      const payload = await response.json();
      if (!response.ok || payload.ok === false) {
        throw new Error(payload.error || "Checklist could not be updated.");
      }

      if (this.hasDeleteFormTarget && form === this.deleteFormTarget) {
        this.closeDeleteModal();
      }

      this.element.outerHTML = payload.html;
      return payload;
    } catch (error) {
      window.alert(error.message || "Checklist could not be updated right now.");
    }
  }

  dragStart(event) {
    if (this.modeValue !== "persisted") {
      return;
    }

    this.draggedElement = event.currentTarget;
    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", this.draggedElement.dataset.itemId || "");
  }

  dragOver(event) {
    if (this.modeValue !== "persisted") {
      return;
    }

    event.preventDefault();
    event.dataTransfer.dropEffect = "move";
  }

  async drop(event) {
    if (this.modeValue !== "persisted") {
      return;
    }

    event.preventDefault();

    const targetElement = event.currentTarget;
    if (!this.draggedElement || this.draggedElement === targetElement) {
      return;
    }

    const reorderUrl = this.draggedElement.dataset.reorderUrl;
    const newPosition = Number.parseInt(targetElement.dataset.position || "", 10);
    if (!reorderUrl || !Number.isFinite(newPosition)) {
      return;
    }

    const formData = new FormData();
    formData.append("_method", "patch");
    formData.append("todo_item[position]", String(newPosition));

    try {
      const response = await fetch(reorderUrl, {
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
        throw new Error(payload.error || "Checklist order could not be updated.");
      }

      this.element.outerHTML = payload.html;
    } catch (error) {
      window.alert(error.message || "Checklist order could not be updated.");
    }
  }

  dragEnd() {
    this.draggedElement = null;
  }

  submitEditedItem(form, input) {
    if (!(form instanceof HTMLFormElement) || !(input instanceof HTMLInputElement || input instanceof HTMLTextAreaElement)) {
      return;
    }

    if (form.dataset.submitting === "true") {
      return;
    }

    const nextValue = this.normalizeValue(input.value);
    const initialValue = this.normalizeValue(input.dataset.initialValue || "");

    if (!nextValue) {
      input.value = input.dataset.initialValue || "";
      this.resizeElement(input);
      return;
    }

    if (nextValue === initialValue) {
      input.value = input.dataset.initialValue || nextValue;
      this.resizeElement(input);
      return;
    }

    input.value = nextValue;
    this.resizeElement(input);
    form.dataset.submitting = "true";
    this.submitForm(form).finally(() => {
      if (form.isConnected) {
        delete form.dataset.submitting;
      }
    });
  }

  renderDraftItems() {
    if (!this.hasDraftItemsTarget || !this.hasDraftFieldsTarget) {
      return;
    }

    this.draftItemsTarget.innerHTML = "";
    this.draftFieldsTarget.innerHTML = "";

    this.pendingDraftItems.forEach((content, index) => {
      const item = document.createElement("div");
      item.className = "todo-list-draft__item";
      item.innerHTML = `
        <span>${content}</span>
        <button type="button" class="btn btn-white btn-sm btn-icon" data-index="${index}" aria-label="Remove draft to-do item">
          <i class="ti ti-x"></i>
        </button>
      `;

      const removeButton = item.querySelector("button");
      removeButton.addEventListener("click", (event) => this.removeDraftItem(event));
      this.draftItemsTarget.appendChild(item);

      const hiddenField = document.createElement("input");
      hiddenField.type = "hidden";
      hiddenField.name = this.draftFieldNameValue;
      hiddenField.value = content;
      this.draftFieldsTarget.appendChild(hiddenField);
    });
  }

  renderPersistedState() {
    if (this.modeValue !== "persisted") {
      return;
    }

    const filter = this.currentFilter();
    const items = this.hasItemsTarget
      ? Array.from(this.itemsTarget.querySelectorAll(".todo-list-item"))
      : [];

    this.updateFilterButtons(filter);

    let visibleCount = 0;
    items.forEach((item) => {
      const completed = item.classList.contains("is-completed");
      const show =
        filter === "all" ||
        (filter === "active" && !completed) ||
        (filter === "done" && completed);

      item.hidden = !show;
      if (show) {
        visibleCount += 1;
      }
    });

    if (this.hasFilterEmptyTarget) {
      this.filterEmptyTarget.textContent = this.emptyStateMessage(filter, items.length);
      this.filterEmptyTarget.hidden = visibleCount > 0;
    }
  }

  currentFilter() {
    return ["all", "active", "done"].includes(this.filterValue) ? this.filterValue : "all";
  }

  updateFilterButtons(activeFilter) {
    if (!this.hasFilterButtonTarget) {
      return;
    }

    this.filterButtonTargets.forEach((button) => {
      const isActive = (button.dataset.filter || "all") === activeFilter;
      button.classList.toggle("is-active", isActive);
      button.setAttribute("aria-pressed", isActive ? "true" : "false");
    });
  }

  emptyStateMessage(filter, totalCount) {
    if (totalCount === 0) {
      return "Add your first item to get started.";
    }

    if (filter === "done") {
      return "No completed items yet.";
    }

    if (filter === "active") {
      return "All tasks are complete.";
    }

    return "No items match this view.";
  }

  restorePersistedFilter() {
    if (this.modeValue !== "persisted") {
      return;
    }

    try {
      if (!this.hasStorageKeyValue || !window.sessionStorage) {
        return;
      }

      const storedFilter = window.sessionStorage.getItem(this.storageCacheKey());
      if (storedFilter) {
        this.filterValue = storedFilter;
      }
    } catch (_error) {
      // Ignore unavailable session storage.
    }
  }

  persistFilter() {
    if (this.modeValue !== "persisted") {
      return;
    }

    try {
      if (!this.hasStorageKeyValue || !window.sessionStorage) {
        return;
      }

      window.sessionStorage.setItem(this.storageCacheKey(), this.currentFilter());
    } catch (_error) {
      // Ignore unavailable session storage.
    }
  }

  storageCacheKey() {
    return `todo-list-filter:${this.storageKeyValue}`;
  }

  resetDeleteConfirmation() {
    if (this.hasDeleteFormTarget) {
      this.deleteFormTarget.action = "";
    }

    if (this.hasDeleteMessageTarget) {
      this.deleteMessageTarget.textContent = this.defaultDeleteMessage;
    }
  }

  showDeleteModal() {
    const ModalClass = window.bootstrap?.Modal;
    if (!ModalClass || !this.hasDeleteModalTarget) {
      return;
    }

    const modal = ModalClass.getInstance(this.deleteModalTarget) || ModalClass.getOrCreateInstance(this.deleteModalTarget);
    modal.show();
  }

  closeDeleteModal() {
    if (this.hasDeleteModalTarget) {
      const ModalClass = window.bootstrap?.Modal;
      if (ModalClass) {
        const modal = ModalClass.getInstance(this.deleteModalTarget) || ModalClass.getOrCreateInstance(this.deleteModalTarget);
        modal.hide();
      }
    }

    document.body.classList.remove("modal-open");
    document.body.style.removeProperty("padding-right");
    document.querySelectorAll(".modal-backdrop").forEach((backdrop) => backdrop.remove());
  }

  normalizeValue(value) {
    return value
      .toString()
      .replace(/\r\n?/g, "\n")
      .split("\n")
      .map((line) => line.replace(/[ \t]+/g, " ").trimEnd())
      .join("\n")
      .trim();
  }

  resizeAllTextareas() {
    this.element.querySelectorAll(".todo-list-composer__input, .todo-list-item__input").forEach((textarea) => {
      this.resizeElement(textarea);
    });
  }

  resizeElement(element) {
    if (!(element instanceof HTMLTextAreaElement)) {
      return;
    }

    const computedMinHeight = Number.parseFloat(window.getComputedStyle(element).minHeight);
    const minHeight = Number.isFinite(computedMinHeight) ? computedMinHeight : 0;

    element.style.height = "0px";
    element.style.height = `${Math.max(element.scrollHeight, minHeight)}px`;
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || "";
  }
}
