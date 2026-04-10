import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = [
    "draftInput",
    "draftItems",
    "draftFields",
    "enabledField",
    "hideCompletedField",
    "toggleButton",
    "draftPanel",
    "items"
  ];

  static values = {
    mode: { type: String, default: "persisted" }
  };

  connect() {
    this.pendingDraftItems = [];
    this.draggedElement = null;
    this.renderDraftItems();
    this.renderDraftState();
  }

  toggleDraftEnabled() {
    if (!this.hasEnabledFieldTarget) {
      return;
    }

    this.enabledFieldTarget.value = this.enabledFieldTarget.value === "true" ? "false" : "true";
    this.renderDraftState();
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
    this.renderDraftItems();
    this.renderDraftState();
  }

  removeDraftItem(event) {
    const index = Number.parseInt(event.currentTarget.dataset.index || "", 10);
    if (!Number.isFinite(index)) {
      return;
    }

    this.pendingDraftItems.splice(index, 1);
    this.renderDraftItems();
  }

  async submit(event) {
    if (this.modeValue !== "persisted") {
      return;
    }

    event.preventDefault();

    const form = event.currentTarget;
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

      this.element.outerHTML = payload.html;
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
      hiddenField.name = "page[todo_item_contents][]";
      hiddenField.value = content;
      this.draftFieldsTarget.appendChild(hiddenField);
    });
  }

  renderDraftState() {
    if (!this.hasEnabledFieldTarget) {
      return;
    }

    const enabled = this.enabledFieldTarget.value === "true";

    if (this.hasToggleButtonTarget) {
      this.toggleButtonTarget.textContent = enabled ? "Disable list" : "Enable list";
    }

    if (this.hasDraftPanelTarget) {
      this.draftPanelTarget.classList.toggle("is-disabled", !enabled);
    }
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || "";
  }
}
