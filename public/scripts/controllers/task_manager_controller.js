import { Controller } from "/scripts/vendor/stimulus.js";

/**
 * TaskManager Stimulus controller
 * Handles: filter switching, sort/group form auto-submit, detail drawer
 * open/close (fetches HTML from the server), priority cycling, keyboard shortcuts.
 */
export default class extends Controller {
  static targets = [
    "quickAddPanel",
    "quickAddInput",
    "list",
    "backdrop",
    "drawer",
    "drawerContent",
    "newModalBackdrop",
    "newModal",
    "newModalInput",
    "linkTypeSelect",
    "linkSearch",
    "linkSearchInput",
    "linkDropdown",
    "linkLabelInput"
  ];

  static values = {
    filter: { type: String, default: "all" }
  };

  // ─── Lifecycle ──────────────────────────────────────────────────────────
  connect() {
    this.boundKeydown = this.handleKeydown.bind(this);
    document.addEventListener("keydown", this.boundKeydown);
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown);
  }

  // ─── Quick-add panel ────────────────────────────────────────────────────
  openQuickAdd() {
    // On mobile (<= 640px) use the bottom-sheet modal instead of the inline panel
    if (window.innerWidth <= 640) {
      this.openNewModal();
      return;
    }
    if (this.hasQuickAddPanelTarget) {
      this.quickAddPanelTarget.style.display = "";
      this.quickAddPanelTarget.removeAttribute("aria-hidden");
      setTimeout(() => this.quickAddInputTarget?.focus(), 60);
    }
  }

  closeQuickAdd() {
    if (this.hasQuickAddPanelTarget) {
      this.quickAddPanelTarget.style.display = "none";
      this.quickAddPanelTarget.setAttribute("aria-hidden", "true");
    }
  }

  handleQuickAddSubmit(event) {
    // Let the form submit normally; just close the panel on success.
    this.closeQuickAdd();
  }

  // ─── New-task modal (bottom sheet on mobile, centred on desktop) ─────────
  openNewModal() {
    if (!this.hasNewModalTarget) return;
    this.newModalBackdropTarget.classList.add("task-new-modal-backdrop--open");
    this.newModalTarget.classList.add("task-new-modal--open");
    this.newModalTarget.removeAttribute("aria-hidden");
    this.newModalBackdropTarget.removeAttribute("aria-hidden");
    document.body.classList.add("task-modal-open");
    setTimeout(() => this.newModalInputTarget?.focus(), 80);
  }

  closeNewModal() {
    if (!this.hasNewModalTarget) return;
    this.newModalBackdropTarget.classList.remove("task-new-modal-backdrop--open");
    this.newModalTarget.classList.remove("task-new-modal--open");
    this.newModalTarget.setAttribute("aria-hidden", "true");
    this.newModalBackdropTarget.setAttribute("aria-hidden", "true");
    document.body.classList.remove("task-modal-open");
  }

  handleNewModalSubmit(event) {
    // Let the form submit normally (Turbo/standard), then close.
    this.closeNewModal();
  }

  // ─── Sort/group form auto-submit ────────────────────────────────────────
  submitSortForm(event) {
    event.target.closest("form")?.submit();
  }

  submitGroupForm(event) {
    event.target.closest("form")?.submit();
  }

  // ─── Task detail drawer ──────────────────────────────────────────────────
  async openDetail(event) {
    const taskId = event.currentTarget.dataset.taskId;
    if (!taskId) return;

    this.backdropTarget.classList.add("task-detail-backdrop--open");
    this.drawerTarget.classList.add("task-detail-drawer--open");
    this.drawerContentTarget.innerHTML = '<div class="task-detail-loading"><i class="ti ti-loader-2 ti-spin"></i> Loading…</div>';

    try {
      const resp = await fetch(`/tasks/${taskId}`, {
        headers: { "Accept": "text/html", "X-Requested-With": "XMLHttpRequest" }
      });
      if (resp.ok) {
        const html = await resp.text();
        this.drawerContentTarget.innerHTML = html;
      } else {
        this.drawerContentTarget.innerHTML = "<p>Could not load task details.</p>";
      }
    } catch (_) {
      this.drawerContentTarget.innerHTML = "<p>Network error. Please try again.</p>";
    }
  }

  closeDetail() {
    this.backdropTarget.classList.remove("task-detail-backdrop--open");
    this.drawerTarget.classList.remove("task-detail-drawer--open");
    setTimeout(() => { this.drawerContentTarget.innerHTML = ""; }, 320);
  }

  // ─── Detail form submit (PATCH via fetch, then refresh list) ────────────
  async handleDetailSubmit(event) {
    event.preventDefault();
    const form = event.target;
    const taskId = form.closest("[data-task-id]")?.dataset.taskId;
    if (!taskId) return;

    const resp = await fetch(form.action, {
      method: "PATCH",
      body: new FormData(form),
      headers: { "X-Requested-With": "XMLHttpRequest" }
    });

    if (resp.ok || resp.redirected) {
      // Reload the page to reflect changes while preserving filter state
      window.location.reload();
    }
  }

  // ─── Priority cycling (flag button on card) ──────────────────────────────
  async cyclePriority(event) {
    const btn = event.currentTarget;
    const taskId = btn.dataset.taskId;
    const current = btn.dataset.taskPriority;
    const order = ["low", "medium", "high", "urgent"];
    const next = order[(order.indexOf(current) + 1) % order.length];

    // Optimistic UI: update the stripe + button color
    const card = document.getElementById(`task-${taskId}`);
    if (card) {
      card.classList.remove(...order.map(p => `task-card--${p}`));
      card.classList.add(`task-card--${next}`);
      const stripe = card.querySelector(".task-card-stripe");
      if (stripe) {
        stripe.className = `task-card-stripe task-stripe--${next}`;
      }
      btn.dataset.taskPriority = next;
      btn.className = btn.className.replace(/task-action-btn--flag-\w+/, `task-action-btn--flag-${next}`);
    }

    // Persist
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content || "";
    const form = new FormData();
    form.append("task[priority]", next);
    form.append("_method", "patch");

    await fetch(`/tasks/${taskId}`, {
      method: "POST",
      body: form,
      headers: { "X-CSRF-Token": csrfToken, "X-Requested-With": "XMLHttpRequest" }
    }).catch(() => {
      // On failure, reload to get server state
      window.location.reload();
    });
  }

  // ─── Link picker combobox ────────────────────────────────────────────────

  // Called when the type <select> changes
  onLinkTypeChange(event) {
    const type = event.target.value;
    this._clearLinkIds();

    if (!type) {
      if (this.hasLinkSearchTarget)      this.linkSearchTarget.hidden = true;
      if (this.hasLinkLabelInputTarget)  this.linkLabelInputTarget.value = "";
      if (this.hasLinkDropdownTarget)    this.linkDropdownTarget.hidden = true;
      return;
    }

    if (this.hasLinkSearchTarget) {
      this.linkSearchTarget.hidden = false;
      this.linkSearchInputTarget.placeholder = `Search ${type}s…`;
      this.linkSearchInputTarget.value = "";
      this.linkDropdownTarget.hidden = true;
      // Auto-load top results immediately
      this._doLinkSearch("", type);
      setTimeout(() => this.linkSearchInputTarget.focus(), 60);
    }
  }

  // Show top results when the search box gains focus (so it feels instant)
  onLinkSearchFocus() {
    if (!this.hasLinkDropdownTarget || !this.linkDropdownTarget.hidden) return;
    const type = this.hasLinkTypeSelectTarget ? this.linkTypeSelectTarget.value : "";
    if (type) this._doLinkSearch(this.linkSearchInputTarget.value, type);
  }

  // Debounced keystroke handler
  onLinkSearchInput(event) {
    clearTimeout(this._linkTimer);
    this._linkTimer = setTimeout(() => {
      const type = this.hasLinkTypeSelectTarget ? this.linkTypeSelectTarget.value : "";
      if (type) this._doLinkSearch(event.target.value, type);
    }, 220);
  }

  onLinkSearchKeydown(event) {
    if (event.key === "Escape") {
      if (this.hasLinkDropdownTarget) this.linkDropdownTarget.hidden = true;
    }
  }

  async _doLinkSearch(q, type) {
    if (!this.hasLinkDropdownTarget) return;
    const dropdown = this.linkDropdownTarget;
    dropdown.innerHTML = '<div class="task-link-searching"><i class="ti ti-loader-2 ti-spin"></i> Searching…</div>';
    dropdown.hidden = false;

    try {
      const url = `/tasks/link_search?type=${encodeURIComponent(type)}&q=${encodeURIComponent(q)}`;
      const resp = await fetch(url, { headers: { Accept: "application/json" } });
      if (!resp.ok) throw new Error("Search failed");
      const results = await resp.json();
      this._renderLinkResults(results, type);
    } catch {
      dropdown.innerHTML = '<div class="task-link-empty">Could not load results.</div>';
    }
  }

  _renderLinkResults(results, type) {
    const dropdown = this.linkDropdownTarget;
    if (!results.length) {
      dropdown.innerHTML = '<div class="task-link-empty">No results found.</div>';
      return;
    }

    const icon = {
      notebook: "ti-notebook",
      chapter:  "ti-bookmark",
      page:     "ti-file-text",
      voice:    "ti-microphone",
      photo:    "ti-photo",
      todo:     "ti-checkbox"
    }[type] || "ti-link";

    dropdown.innerHTML = results.map(r => {
      // Encode each data field individually to avoid JSON injection in HTML attributes
      const attrs = [
        `data-link-notebook-id="${this._esc(r.link_notebook_id)}"`,
        `data-link-chapter-id="${this._esc(r.link_chapter_id)}"`,
        `data-link-page-id="${this._esc(r.link_page_id)}"`,
        `data-link-resource-id="${this._esc(r.link_resource_id)}"`,
        `data-link-label="${this._esc(r.label)}"`,
      ].join(" ");
      return `<button type="button" class="task-link-result"
                      data-action="click->task-manager#selectLinkResult"
                      ${attrs}>
                <i class="ti ${icon} task-link-result-icon" aria-hidden="true"></i>
                <span class="task-link-result-label">${this._esc(r.label)}</span>
              </button>`;
    }).join("");
  }

  selectLinkResult(event) {
    const btn = event.currentTarget;
    const label = btn.dataset.linkLabel || "";
    this._setLinkField("task[link_notebook_id]", btn.dataset.linkNotebookId);
    this._setLinkField("task[link_chapter_id]",  btn.dataset.linkChapterId);
    this._setLinkField("task[link_page_id]",      btn.dataset.linkPageId);
    this._setLinkField("task[link_resource_id]",  btn.dataset.linkResourceId);
    if (this.hasLinkLabelInputTarget)  this.linkLabelInputTarget.value = label;
    if (this.hasLinkSearchInputTarget) this.linkSearchInputTarget.value = "";
    if (this.hasLinkDropdownTarget)    this.linkDropdownTarget.hidden = true;
  }

  // ─── Clear link in detail form ───────────────────────────────────────────
  clearLink(event) {
    if (this.hasLinkTypeSelectTarget)  this.linkTypeSelectTarget.value = "";
    if (this.hasLinkLabelInputTarget)  this.linkLabelInputTarget.value = "";
    if (this.hasLinkSearchTarget)      this.linkSearchTarget.hidden = true;
    if (this.hasLinkDropdownTarget)    this.linkDropdownTarget.hidden = true;
    this._clearLinkIds();
    // Hide the existing pill
    const pill = event.currentTarget.closest(".task-link-current-pill");
    if (pill) pill.style.display = "none";
  }

  // ─── Link helpers ─────────────────────────────────────────────────────────
  _clearLinkIds() {
    ["link_notebook_id", "link_chapter_id", "link_page_id", "link_resource_id"].forEach(f => {
      this._setLinkField(`task[${f}]`, "");
    });
  }

  _setLinkField(name, value) {
    const el = this.drawerContentTarget.querySelector(`[name="${name}"]`);
    if (el) el.value = value || "";
  }

  _esc(str) {
    if (str == null) return "";
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/"/g, "&quot;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  // ─── Keyboard shortcuts ──────────────────────────────────────────────────
  handleKeydown(event) {
    const typing = /input|textarea|select/i.test(event.target.tagName);

    // Esc: close detail drawer / modals / quick-add
    if (event.key === "Escape") {
      if (this.drawerTarget?.classList.contains("task-detail-drawer--open")) {
        this.closeDetail();
      } else if (this.hasNewModalTarget && this.newModalTarget.classList.contains("task-new-modal--open")) {
        this.closeNewModal();
      } else {
        this.closeQuickAdd();
      }
      return;
    }

    if (typing) return;

    // N: open quick-add
    if (event.key === "n" || event.key === "N") {
      this.openQuickAdd();
    }
  }
}
