import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static values = {
    autoSubmit: Boolean,
    formId: String,
    recordLabel: String
  };

  static targets = [
    "closeButton",
    "contactsInput",
    "deleteButton",
    "emailInput",
    "modal",
    "modalStatus",
    "modalTitle",
    "nameInput",
    "primaryPhoneInput",
    "saveButton",
    "secondaryPhoneInput",
    "status",
    "summary",
    "websiteInput"
  ];

  connect() {
    this.contacts = this.readStoredContacts();
    this.formElement = this.findFormElement();
    this.activeContactIndex = null;
    this.cacheModalElements();
    this.boundHandleClick = this.handleClick.bind(this);
    this.boundSaveContact = this.saveContact.bind(this);
    this.boundDeleteCurrentContact = this.deleteCurrentContact.bind(this);
    this.boundCloseModal = this.closeModal.bind(this);
    this.boundHandleModalShown = this.handleModalShown.bind(this);
    this.boundHandleModalHidden = this.handleModalHidden.bind(this);
    this.element.addEventListener("click", this.boundHandleClick);
    this.bindModalControls();
    this.modalElement?.addEventListener("shown.bs.modal", this.boundHandleModalShown);
    this.modalElement?.addEventListener("hidden.bs.modal", this.boundHandleModalHidden);
    this.renderSummary();
  }

  disconnect() {
    this.element.removeEventListener("click", this.boundHandleClick);
    this.unbindModalControls();
    this.modalElement?.removeEventListener("shown.bs.modal", this.boundHandleModalShown);
    this.modalElement?.removeEventListener("hidden.bs.modal", this.boundHandleModalHidden);
    this.disposeModalInstance();
    this.removeStaleBackdrops();
  }

  cacheModalElements() {
    this.modalElement = this.hasModalTarget ? this.modalTarget : null;
    this.modalStatusElement = this.hasModalStatusTarget ? this.modalStatusTarget : null;
    this.modalTitleElement = this.hasModalTitleTarget ? this.modalTitleTarget : null;
    this.nameInputElement = this.hasNameInputTarget ? this.nameInputTarget : null;
    this.primaryPhoneInputElement = this.hasPrimaryPhoneInputTarget ? this.primaryPhoneInputTarget : null;
    this.secondaryPhoneInputElement = this.hasSecondaryPhoneInputTarget ? this.secondaryPhoneInputTarget : null;
    this.emailInputElement = this.hasEmailInputTarget ? this.emailInputTarget : null;
    this.websiteInputElement = this.hasWebsiteInputTarget ? this.websiteInputTarget : null;
    this.saveButtonElement = this.hasSaveButtonTarget ? this.saveButtonTarget : null;
    this.deleteButtonElement = this.hasDeleteButtonTarget ? this.deleteButtonTarget : null;
    this.closeButtonElements = this.hasCloseButtonTarget ? [...this.closeButtonTargets] : [];
  }

  handleClick(event) {
    const actionElement = event.target.closest("[data-contact-cards-action]");
    if (!(actionElement instanceof HTMLElement) || !this.element.contains(actionElement)) {
      return;
    }

    const syntheticEvent = {
      preventDefault: () => event.preventDefault(),
      currentTarget: actionElement,
      target: event.target
    };

    switch (actionElement.dataset.contactCardsAction) {
      case "open-new":
        this.openNewContact(syntheticEvent);
        break;
      case "edit-contact":
        this.editContact(syntheticEvent);
        break;
      case "save-to-contacts":
        this.saveToContacts(syntheticEvent);
        break;
      case "share-contact":
        this.shareContact(syntheticEvent);
        break;
      default:
        break;
    }
  }

  openNewContact(event) {
    event?.preventDefault();
    this.activeContactIndex = null;
    this.populateEditor({});
    this.updateModalCopy();
    this.clearModalStatus();
    this.showModal();
  }

  editContact(event) {
    event?.preventDefault();

    const index = Number.parseInt(event.currentTarget.dataset.contactIndex || "", 10);
    const contact = this.contacts[index];
    if (!contact) return;

    this.activeContactIndex = index;
    this.populateEditor(contact);
    this.updateModalCopy();
    this.clearModalStatus();
    this.showModal();
  }

  saveContact(event) {
    event?.preventDefault();

    const { contact, error } = this.contactFromEditor();
    if (!contact) {
      this.setModalStatus(error || "Add a contact name and at least one contact detail.", "error");
      return;
    }

    if (this.duplicateContact(contact)) {
      this.setModalStatus("That contact is already saved.", "error");
      return;
    }

    const nextContacts = [...this.contacts];
    if (Number.isInteger(this.activeContactIndex)) {
      nextContacts[this.activeContactIndex] = contact;
    } else {
      nextContacts.push(contact);
    }

    this.storeContacts(nextContacts);
    this.hideModal();
    this.setStatus(Number.isInteger(this.activeContactIndex) ? "Contact updated." : "Contact added.", "success");
    this.autoSubmitIfNeeded();
  }

  deleteCurrentContact(event) {
    event?.preventDefault();

    if (!Number.isInteger(this.activeContactIndex)) {
      return;
    }

    this.storeContacts(this.contacts.filter((_contact, index) => index !== this.activeContactIndex));
    this.hideModal();
    this.setStatus("Contact removed.", "success");
    this.autoSubmitIfNeeded();
  }

  closeModal(event) {
    event?.preventDefault();
    this.hideModal();
  }

  saveToContacts(event) {
    event?.preventDefault();

    const contact = this.contactAt(event.currentTarget.dataset.contactIndex);
    if (!contact) return;

    const payload = this.vcardPayload(contact);
    this.openVcard(payload);
    this.setStatus("Contact card opened.", "info");
  }

  async shareContact(event) {
    event?.preventDefault();

    const contact = this.contactAt(event.currentTarget.dataset.contactIndex);
    if (!contact) return;

    const payload = this.vcardPayload(contact);

    try {
      if (payload.file && typeof navigator.canShare === "function" && navigator.canShare({ files: [payload.file] })) {
        await navigator.share({
          title: contact.name,
          text: `Contact card for ${contact.name}`,
          files: [payload.file]
        });
        this.setStatus("Contact shared.", "success");
        return;
      }

      if (typeof navigator.share === "function") {
        await navigator.share({
          title: contact.name,
          text: this.shareText(contact)
        });
        this.setStatus("Contact shared.", "success");
        return;
      }

      this.downloadVcard(payload);
      this.setStatus("Sharing is unavailable here, so the vCard was downloaded.", "info");
    } catch (error) {
      if (error?.name === "AbortError") {
        return;
      }

      this.setStatus("Could not share the contact on this device.", "error");
    }
  }

  renderSummary() {
    if (!this.contacts.length) {
      this.summaryTarget.innerHTML = "<div class=\"contact-section__summary-empty\">No contact added yet.</div>";
      return;
    }

    const countLabel = this.contacts.length === 1 ? "1 contact saved" : `${this.contacts.length} contacts saved`;
    const cards = this.contacts.map((contact, index) => this.contactCardMarkup(contact, index)).join("");

    this.summaryTarget.innerHTML = [
      `<div class="contact-section__summary-count">${this.escapeHtml(countLabel)}</div>`,
      `<div class="contact-section__summary-list">${cards}</div>`
    ].join("");
  }

  storeContacts(contacts) {
    this.contacts = this.normalizeContacts(contacts);
    this.contactsInputTarget.value = JSON.stringify(this.contacts);
    this.renderSummary();
  }

  readStoredContacts() {
    try {
      const rawValue = this.contactsInputTarget.value.trim();
      if (!rawValue) return [];

      return this.normalizeContacts(JSON.parse(rawValue));
    } catch (_error) {
      return [];
    }
  }

  normalizeContacts(contacts) {
    const seenSignatures = new Set();

    return Array.from(Array.isArray(contacts) ? contacts : [])
      .map((contact) => this.normalizeContact(contact))
      .filter((contact) => {
        if (!contact) return false;

        const signature = this.contactSignature(contact);
        if (seenSignatures.has(signature)) return false;

        seenSignatures.add(signature);
        return true;
      });
  }

  normalizeContact(contact) {
    if (!contact || typeof contact !== "object") {
      return null;
    }

    const normalizedContact = {
      name: this.trimmedValue(contact.name),
      primary_phone: this.trimmedPhone(contact.primary_phone || contact.phone),
      secondary_phone: this.trimmedPhone(contact.secondary_phone),
      email: this.trimmedValue(contact.email),
      website: this.trimmedValue(contact.website)
    };

    if (!Object.values(normalizedContact).some(Boolean)) {
      return null;
    }

    return normalizedContact;
  }

  contactFromEditor() {
    const contact = this.normalizeContact({
      name: this.nameInputElement?.value,
      primary_phone: this.primaryPhoneInputElement?.value,
      secondary_phone: this.secondaryPhoneInputElement?.value,
      email: this.emailInputElement?.value,
      website: this.websiteInputElement?.value
    });

    if (!contact) {
      return { contact: null, error: "Add a contact name and at least one contact detail." };
    }

    if (!contact.name) {
      return { contact: null, error: "Contact name is required." };
    }

    if (!this.contactHasAnyDetail(contact)) {
      return { contact: null, error: "Add a phone number, email, or website." };
    }

    if (contact.email && !this.validEmail(contact.email)) {
      return { contact: null, error: "Enter a valid email address." };
    }

    if (contact.website && !this.websiteUrl(contact.website)) {
      return { contact: null, error: "Enter a valid website." };
    }

    if (contact.primary_phone && !this.validPhone(contact.primary_phone)) {
      return { contact: null, error: "Enter a valid primary phone number." };
    }

    if (contact.secondary_phone && !this.validPhone(contact.secondary_phone)) {
      return { contact: null, error: "Enter a valid secondary phone number." };
    }

    return { contact, error: null };
  }

  contactHasAnyDetail(contact) {
    return Boolean(contact.primary_phone || contact.secondary_phone || contact.email || contact.website);
  }

  duplicateContact(contact) {
    const signature = this.contactSignature(contact);

    return this.contacts.some((existingContact, index) => {
      if (Number.isInteger(this.activeContactIndex) && index === this.activeContactIndex) {
        return false;
      }

      return this.contactSignature(existingContact) === signature;
    });
  }

  contactSignature(contact) {
    return [
      (contact.name || "").toLowerCase(),
      this.sanitizedPhone(contact.primary_phone),
      this.sanitizedPhone(contact.secondary_phone),
      (contact.email || "").toLowerCase(),
      (this.websiteUrl(contact.website) || "").toLowerCase()
    ].join("|");
  }

  contactAt(indexValue) {
    const index = Number.parseInt(indexValue || "", 10);
    return Number.isInteger(index) ? this.contacts[index] : null;
  }

  populateEditor(contact) {
    if (this.nameInputElement) this.nameInputElement.value = contact.name || "";
    if (this.primaryPhoneInputElement) this.primaryPhoneInputElement.value = contact.primary_phone || "";
    if (this.secondaryPhoneInputElement) this.secondaryPhoneInputElement.value = contact.secondary_phone || "";
    if (this.emailInputElement) this.emailInputElement.value = contact.email || "";
    if (this.websiteInputElement) this.websiteInputElement.value = contact.website || "";
  }

  resetEditor() {
    this.activeContactIndex = null;
    this.populateEditor({});
    this.updateModalCopy();
    this.clearModalStatus();
  }

  updateModalCopy() {
    const editing = Number.isInteger(this.activeContactIndex);

    if (this.modalTitleElement) {
      this.modalTitleElement.textContent = editing ? "Edit contact" : "Add contact";
    }

    if (this.saveButtonElement) {
      this.saveButtonElement.textContent = editing ? "Save changes" : "Save contact";
    }

    if (this.deleteButtonElement) {
      this.deleteButtonElement.hidden = !editing;
    }
  }

  showModal() {
    const modalInstance = this.bootstrapModalInstance();
    if (!modalInstance) {
      this.focusNameInput();
      return;
    }

    modalInstance.show();
  }

  bindModalControls() {
    if (this.saveButtonElement) {
      this.saveButtonElement.addEventListener("click", this.boundSaveContact);
    }

    if (this.deleteButtonElement) {
      this.deleteButtonElement.addEventListener("click", this.boundDeleteCurrentContact);
    }

    this.closeButtonElements.forEach((button) => {
      button.addEventListener("click", this.boundCloseModal);
    });
  }

  unbindModalControls() {
    if (this.saveButtonElement) {
      this.saveButtonElement.removeEventListener("click", this.boundSaveContact);
    }

    if (this.deleteButtonElement) {
      this.deleteButtonElement.removeEventListener("click", this.boundDeleteCurrentContact);
    }

    this.closeButtonElements.forEach((button) => {
      button.removeEventListener("click", this.boundCloseModal);
    });
  }

  hideModal() {
    const modalInstance = this.bootstrapModalInstance();
    if (!modalInstance) {
      this.resetEditor();
      return;
    }

    modalInstance.hide();

    // Guard against stale backdrops or a stuck modal instance after animated closes.
    window.setTimeout(() => {
      if (this.modalVisible()) {
        return;
      }

      this.removeStaleBackdrops();
      document.body.classList.remove("modal-open");
      document.body.style.removeProperty("padding-right");
    }, 350);
  }

  handleModalShown() {
    this.focusNameInput();
  }

  handleModalHidden() {
    this.resetEditor();
    this.disposeModalInstance();
    this.removeStaleBackdrops();
    document.body.classList.remove("modal-open");
    document.body.style.removeProperty("padding-right");
  }

  bootstrapModalInstance() {
    const ModalClass = window.bootstrap?.Modal;
    if (!ModalClass || !this.modalElement) {
      return null;
    }

    this.modalInstance = ModalClass.getOrCreateInstance(this.modalElement);
    return this.modalInstance;
  }

  disposeModalInstance() {
    if (!this.modalInstance?.dispose) {
      this.modalInstance = null;
      return;
    }

    this.modalInstance.dispose();
    this.modalInstance = null;
  }

  removeStaleBackdrops() {
    document.querySelectorAll(".modal-backdrop").forEach((backdrop) => backdrop.remove());
  }

  modalVisible() {
    return this.modalElement?.classList.contains("show") || false;
  }

  focusNameInput() {
    if (!this.nameInputElement) return;

    this.nameInputElement.focus({ preventScroll: true });
    if (typeof this.nameInputElement.select === "function") {
      this.nameInputElement.select();
    }
  }

  findFormElement() {
    if (this.hasFormIdValue && this.formIdValue) {
      return document.getElementById(this.formIdValue);
    }

    return this.element.closest("form");
  }

  autoSubmitIfNeeded() {
    if (!this.autoSubmitValue || !this.formElement) {
      return;
    }

    if (this.autoSubmitPending) {
      this.autoSubmitQueued = true;
      return;
    }

    this.performAutoSubmit();
  }

  async performAutoSubmit() {
    this.autoSubmitPending = true;

    try {
      do {
        this.autoSubmitQueued = false;
        this.setStatus("Saving contact...", "info");

        const headers = {
          Accept: "text/vnd.turbo-stream.html, text/html, application/xhtml+xml",
          "X-Requested-With": "XMLHttpRequest"
        };
        const csrfToken = this.csrfToken();
        if (csrfToken) {
          headers["X-CSRF-Token"] = csrfToken;
        }

        const response = await fetch(this.formElement.action, {
          method: (this.formElement.method || "post").toUpperCase(),
          body: new FormData(this.formElement),
          credentials: "same-origin",
          headers
        });

        if (!response.ok) {
          throw new Error(`Autosave request failed with status ${response.status}`);
        }
      } while (this.autoSubmitQueued);

      this.setStatus("Contact saved.", "success");
    } catch (_error) {
      this.setStatus("Contact could not be saved right now.", "error");
    } finally {
      this.autoSubmitPending = false;
    }
  }

  csrfToken() {
    const formTokenField = this.formElement?.querySelector("input[name='authenticity_token']");
    if (formTokenField?.value) {
      return formTokenField.value;
    }

    return document.querySelector("meta[name='csrf-token']")?.content || "";
  }

  setStatus(message, tone = "info") {
    if (!this.hasStatusTarget) return;

    this.statusTarget.textContent = message || "";
    this.statusTarget.dataset.tone = tone;
  }

  setModalStatus(message, tone = "error") {
    if (!this.modalStatusElement) return;

    const text = String(message || "").trim();
    this.modalStatusElement.hidden = text.length === 0;
    this.modalStatusElement.textContent = text;
    this.modalStatusElement.dataset.tone = tone;
  }

  clearModalStatus() {
    if (!this.modalStatusElement) return;

    this.modalStatusElement.hidden = true;
    this.modalStatusElement.textContent = "";
    delete this.modalStatusElement.dataset.tone;
  }

  contactCardMarkup(contact, index) {
    const details = [
      this.contactDetailMarkup("ti-phone", "Primary", contact.primary_phone, contact.primary_phone ? `tel:${this.escapeHtml(this.sanitizedPhone(contact.primary_phone))}` : ""),
      this.contactDetailMarkup("ti-phone-call", "Secondary", contact.secondary_phone, contact.secondary_phone ? `tel:${this.escapeHtml(this.sanitizedPhone(contact.secondary_phone))}` : ""),
      this.contactDetailMarkup("ti-mail", "Email", contact.email, contact.email ? `mailto:${this.escapeHtml(contact.email)}` : ""),
      this.contactDetailMarkup("ti-world", "Website", contact.website, this.websiteUrl(contact.website))
    ].filter(Boolean).join("");

    return [
      "<div class=\"contact-section__summary-card\">",
      "  <div class=\"contact-section__summary-card-main\">",
      `    <div class="contact-section__summary-title">${this.escapeHtml(contact.name)}</div>`,
      `    <div class="contact-section__summary-details">${details}</div>`,
      "  </div>",
      "  <div class=\"contact-section__summary-actions\">",
      `    <button type="button" class="contact-section__summary-action" data-contact-cards-action="save-to-contacts" data-contact-index="${index}"><i class="ti ti-user-plus" aria-hidden="true"></i><span>Save contact</span></button>`,
      `    <button type="button" class="contact-section__summary-action" data-contact-cards-action="share-contact" data-contact-index="${index}"><i class="ti ti-share" aria-hidden="true"></i><span>Share</span></button>`,
      `    <button type="button" class="contact-section__summary-action" data-contact-cards-action="edit-contact" data-contact-index="${index}"><i class="ti ti-pencil" aria-hidden="true"></i><span>Edit</span></button>`,
      "  </div>",
      "</div>"
    ].join("");
  }

  contactDetailMarkup(icon, label, value, href = "") {
    if (!value) return "";

    const content = [
      `<span class="contact-section__detail-label">${this.escapeHtml(label)}</span>`,
      `<span class="contact-section__detail-value">${this.escapeHtml(value)}</span>`
    ].join("");

    if (href) {
      return `<a class="contact-section__summary-detail-row contact-section__summary-detail-row--link" href="${href}" target="_blank" rel="noopener"><i class="ti ${icon}" aria-hidden="true"></i>${content}</a>`;
    }

    return `<div class="contact-section__summary-detail-row"><i class="ti ${icon}" aria-hidden="true"></i>${content}</div>`;
  }

  shareText(contact) {
    return [
      contact.name,
      contact.primary_phone ? `Primary phone: ${contact.primary_phone}` : "",
      contact.secondary_phone ? `Secondary phone: ${contact.secondary_phone}` : "",
      contact.email ? `Email: ${contact.email}` : "",
      contact.website ? `Website: ${this.websiteUrl(contact.website) || contact.website}` : ""
    ].filter(Boolean).join("\n");
  }

  vcardPayload(contact) {
    const fileName = this.vcardFileName(contact);
    const blob = new Blob([this.vcardString(contact)], { type: "text/vcard;charset=utf-8" });
    const file = typeof File === "function" ? new File([blob], fileName, { type: blob.type }) : null;

    return { blob, file, fileName };
  }

  vcardString(contact) {
    const website = this.websiteUrl(contact.website) || contact.website || "";

    return [
      "BEGIN:VCARD",
      "VERSION:3.0",
      `FN:${this.escapeVcard(contact.name)}`,
      `N:;${this.escapeVcard(contact.name)};;;`,
      contact.primary_phone ? `TEL;TYPE=CELL,VOICE:${this.escapeVcard(contact.primary_phone)}` : "",
      contact.secondary_phone ? `TEL;TYPE=OTHER:${this.escapeVcard(contact.secondary_phone)}` : "",
      contact.email ? `EMAIL;TYPE=INTERNET:${this.escapeVcard(contact.email)}` : "",
      website ? `URL:${this.escapeVcard(website)}` : "",
      this.recordLabelValue ? `NOTE:${this.escapeVcard(`Saved from ${this.recordLabelValue}`)}` : "",
      "END:VCARD"
    ].filter(Boolean).join("\r\n");
  }

  openVcard({ blob, fileName }) {
    this.navigateToBlob(blob, fileName, { download: false });
  }

  downloadVcard({ blob, fileName }) {
    this.navigateToBlob(blob, fileName, { download: true });
  }

  navigateToBlob(blob, fileName, { download = false } = {}) {
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");

    link.href = url;
    link.rel = "noopener";
    if (download) {
      link.download = fileName;
    } else {
      link.target = "_blank";
    }

    document.body.appendChild(link);
    link.click();
    link.remove();

    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  vcardFileName(contact) {
    const slug = (contact.name || "contact")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "") || "contact";

    return `${slug}.vcf`;
  }

  validEmail(value) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
  }

  validPhone(value) {
    return this.sanitizedPhone(value).replace(/\D/g, "").length >= 5;
  }

  sanitizedPhone(value) {
    return String(value || "").replace(/[^\d+*#;,]/g, "");
  }

  websiteUrl(value) {
    const rawValue = this.trimmedValue(value);
    if (!rawValue) return "";

    try {
      const candidate = /^https?:\/\//i.test(rawValue) ? rawValue : `https://${rawValue}`;
      const url = new URL(candidate);
      return /^https?:$/i.test(url.protocol) ? url.toString() : "";
    } catch (_error) {
      return "";
    }
  }

  trimmedValue(value) {
    return String(value || "").trim().replace(/\s+/g, " ");
  }

  trimmedPhone(value) {
    return this.trimmedValue(value);
  }

  escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  escapeVcard(value) {
    return String(value || "")
      .replace(/\\/g, "\\\\")
      .replace(/\n/g, "\\n")
      .replace(/,/g, "\\,")
      .replace(/;/g, "\\;");
  }
}
