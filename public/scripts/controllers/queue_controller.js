import { Controller } from "/scripts/vendor/stimulus.js";
import { localStore } from "../indexed-db.js";

export default class extends Controller {
  static targets = ["form"];

  connect() {
    this.file = null;
    this.previewDataUrl = null;
    this.element.addEventListener("inkcreate:file-selected", (event) => {
      this.file = event.detail.file;
      this.previewDataUrl = event.detail.previewDataUrl;
    });
  }

  attachFile(event) {
    const [file] = event.target.files || [];
    if (!file) {
      return;
    }

    this.file = file;
  }

  async saveDraft() {
    window.InkcreatePageLoader?.show(
      this.file
        ? (navigator.onLine ? "Uploading your photo..." : "Saving your photo draft locally...")
        : "Saving your draft..."
    );

    const draft = this.buildDraft();
    await localStore.put(localStore.stores.drafts, draft);

    if (this.file) {
      await localStore.put(localStore.stores.uploads, {
        id: draft.id,
        draft,
        file: this.file,
        csrfToken: this.csrfToken()
      });
      await this.registerSync();
    }

    if (navigator.onLine && this.file) {
      try {
        const capture = await this.uploadDraft(draft, this.file);
        await localStore.delete(localStore.stores.drafts, draft.id);
        await localStore.delete(localStore.stores.uploads, draft.id);
        window.location.href = `/captures/${capture.id}`;
        return;
      } catch (_error) {
        window.InkcreatePageLoader?.hide();
        // Keep the queued upload locally. The service worker replay path will retry it.
      }
    }

    window.InkcreatePageLoader?.hide();
    window.alert("Draft saved locally. It will stay available offline and retry upload when possible.");
  }

  buildDraft() {
    const formData = new FormData(this.formTarget);
    return {
      id: crypto.randomUUID(),
      title: formData.get("title"),
      page_type: formData.get("page_type") || "blank",
      project_id: formData.get("project_id") || null,
      physical_page_id: formData.get("physical_page_id") || null,
      save_destination: formData.get("save_destination") || null,
      metadata: {
        source: "pwa_capture",
        previewDataUrl: this.previewDataUrl
      },
      created_at: new Date().toISOString()
    };
  }

  async uploadDraft(draft, file) {
    const uploadResponse = await fetch("/api/v1/upload_urls", {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({
        upload: {
          filename: file.name,
          content_type: file.type,
          byte_size: file.size
        }
      })
    });

    if (!uploadResponse.ok) {
      throw new Error("Unable to request upload URL");
    }

    const upload = await uploadResponse.json();
    const uploadResult = await fetch(upload.signed_url, {
      method: "PUT",
      headers: upload.headers,
      body: file
    });

    if (!uploadResult.ok) {
      throw new Error("Direct upload failed");
    }

    const createResponse = await fetch("/api/v1/captures", {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({
        capture: {
          project_id: draft.project_id,
          physical_page_id: draft.physical_page_id,
          page_type: draft.page_type,
          page_template_key: draft.page_type,
          title: draft.title,
          object_key: upload.object_key,
          original_filename: file.name,
          save_destination: draft.save_destination,
          client_draft_id: draft.id,
          metadata: draft.metadata
        }
      })
    });

    if (!createResponse.ok) {
      throw new Error("Capture create failed");
    }

    const payload = await createResponse.json();
    return payload.capture;
  }

  async registerSync() {
    if ("serviceWorker" in navigator) {
      const registration = await navigator.serviceWorker.ready;

      if ("sync" in registration) {
        await registration.sync.register("inkcreate-sync");
      }
    }
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || "";
  }
}
