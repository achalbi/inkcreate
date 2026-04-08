const syncShellOverlay = (overlay) => {
  if (!(overlay instanceof HTMLElement)) {
    return;
  }

  const sidebarActive = overlay.dataset.sidebarActive === "true";
  const dropdownActive = overlay.dataset.dropdownActive === "true";

  overlay.classList.toggle("show", sidebarActive || dropdownActive);
};

const setShellOverlayFlag = (overlay, key, active) => {
  if (!(overlay instanceof HTMLElement)) {
    return;
  }

  overlay.dataset[key] = active ? "true" : "false";
  syncShellOverlay(overlay);
};

const findBackdropDropdownToggle = (source) => {
  if (!(source instanceof HTMLElement)) {
    return null;
  }

  if (source.matches("[data-shell-dropdown-backdrop]")) {
    return source;
  }

  return source.querySelector("[data-shell-dropdown-backdrop]");
};

const hasBackdropDropdownOpen = () =>
  document.querySelector("[data-shell-dropdown-backdrop][aria-expanded='true']") instanceof HTMLElement;

const closeBackdropDropdowns = () => {
  const toggles = new Set();

  document.querySelectorAll(".dropdown-menu.show").forEach((menu) => {
    const toggle = menu.closest(".dropdown")?.querySelector("[data-shell-dropdown-backdrop]");
    if (toggle instanceof HTMLElement) {
      toggles.add(toggle);
    }
  });

  document.querySelectorAll("[data-shell-dropdown-backdrop][aria-expanded='true']").forEach((toggle) => {
    if (toggle instanceof HTMLElement) {
      toggles.add(toggle);
    }
  });

  toggles.forEach((toggle) => {
    window.bootstrap?.Dropdown.getOrCreateInstance(toggle).hide();
  });
};

const bindWorkspaceShell = () => {
  if (document.body.dataset.workspaceShellBound === "true") {
    return;
  }

  const sidebar = document.getElementById("sidebar");
  const content = document.getElementById("content");
  const topbar = document.getElementById("topbar");
  const toggleBtn = document.getElementById("toggleBtn");
  const mobileBtn = document.getElementById("mobileBtn");
  const overlay = document.getElementById("overlay");

  if (overlay) {
    overlay.dataset.sidebarActive = overlay.dataset.sidebarActive || "false";
    overlay.dataset.dropdownActive = overlay.dataset.dropdownActive || "false";
    syncShellOverlay(overlay);
  }

  if (toggleBtn) {
    toggleBtn.addEventListener("click", () => {
      if (sidebar) sidebar.classList.toggle("collapsed");
      if (content) content.classList.toggle("full");
      if (topbar) topbar.classList.toggle("full");
    });
  }

  if (mobileBtn) {
    mobileBtn.addEventListener("click", () => {
      if (sidebar) sidebar.classList.add("mobile-show");
      setShellOverlayFlag(overlay, "sidebarActive", true);
    });
  }

  if (overlay) {
    overlay.addEventListener("click", () => {
      if (sidebar) sidebar.classList.remove("mobile-show");
      setShellOverlayFlag(overlay, "sidebarActive", false);
      closeBackdropDropdowns();
    });
  }

  document.body.dataset.workspaceShellBound = "true";
};

const bindCardLinks = () => {
  if (document.body.dataset.workspaceCardLinksBound === "true") {
    return;
  }

  const interactiveSelector = "a, button, input, select, textarea, label, summary";
  const navigateToCardLink = (card) => {
    const href = card?.dataset.cardLink;
    if (!href) return;

    window.location.assign(href);
  };

  document.addEventListener("click", (event) => {
    if (event.defaultPrevented) return;
    if (event.target.closest(interactiveSelector)) return;

    const card = event.target.closest("[data-card-link]");
    if (!card) return;
    if (window.getSelection && window.getSelection().toString()) return;

    navigateToCardLink(card);
  });

  document.addEventListener("keydown", (event) => {
    if (event.defaultPrevented) return;
    if (event.key !== "Enter" && event.key !== " ") return;
    if (!event.target.matches("[data-card-link]")) return;

    event.preventDefault();
    navigateToCardLink(event.target);
  });

  document.body.dataset.workspaceCardLinksBound = "true";
};

let workspacePhotoLightboxBound = false;
let workspacePhotoLightboxPromise = null;
let workspaceModalPortalsBound = false;
let workspaceDropdownBackdropsBound = false;

const bindPhotoLightbox = () => {
  if (workspacePhotoLightboxBound) {
    return;
  }

  const collectGalleryItems = (trigger) => {
    const galleryGroup = trigger.dataset.photoLightboxGroup || "workspace-gallery";
    return Array.from(document.querySelectorAll("[data-photoswipe-item]"))
      .filter((item) => (item.dataset.photoLightboxGroup || "workspace-gallery") === galleryGroup)
      .map((item) => {
        const previewImage = item.querySelector("img");
        const fallbackWidth = Number.parseInt(item.dataset.pswpWidth || "", 10);
        const fallbackHeight = Number.parseInt(item.dataset.pswpHeight || "", 10);
        const width = previewImage?.naturalWidth || previewImage?.width || fallbackWidth || 1600;
        const height = previewImage?.naturalHeight || previewImage?.height || fallbackHeight || 1200;

        return {
          src: item.dataset.pswpSrc || item.getAttribute("href") || "",
          msrc: previewImage?.currentSrc || previewImage?.src || item.dataset.pswpSrc || item.getAttribute("href") || "",
          alt: item.dataset.photoLightboxAlt || previewImage?.alt || "Photo preview",
          width,
          height,
          thumbEl: previewImage || item,
          element: item
        };
      });
  };

  const setupPhotoLightbox = async () => {
    if (workspacePhotoLightboxPromise) {
      return workspacePhotoLightboxPromise;
    }

    workspacePhotoLightboxPromise = import("/vendor/photoswipe/photoswipe-lightbox.esm.js")
      .then(({ default: PhotoSwipeLightbox }) => {
        const lightbox = new PhotoSwipeLightbox({
          bgOpacity: 0.92,
          pswpModule: () => import("/vendor/photoswipe/photoswipe.esm.js")
        });

        lightbox.addFilter("thumbEl", (thumbEl, data) => data.thumbEl || data.element || thumbEl);
        lightbox.addFilter("placeholderSrc", (placeholderSrc, slide) => slide.data.msrc || placeholderSrc);

        lightbox.on("uiRegister", () => {
          lightbox.pswp.ui.registerElement({
            name: "custom-caption",
            className: "pswp__custom-caption",
            appendTo: "root",
            onInit: (element, pswp) => {
              const updateCaption = () => {
                const caption = pswp.currSlide?.data?.alt?.trim() || "";
                element.textContent = caption;
                element.hidden = caption.length === 0;
              };

              pswp.on("change", updateCaption);
              updateCaption();
            }
          });
        });

        lightbox.init();
        return lightbox;
      })
      .catch((error) => {
        workspacePhotoLightboxPromise = null;
        throw error;
      });

    return workspacePhotoLightboxPromise;
  };

  document.addEventListener("click", async (event) => {
    const trigger = event.target.closest("[data-photoswipe-item]");
    if (!trigger) {
      return;
    }

    event.preventDefault();

    const galleryItems = collectGalleryItems(trigger);
    const triggerIndex = galleryItems.findIndex((item) => item.element === trigger);

    if (galleryItems.length === 0) {
      window.open(trigger.getAttribute("href"), "_blank", "noopener,noreferrer");
      return;
    }

    try {
      const lightbox = await setupPhotoLightbox();
      lightbox.loadAndOpen(triggerIndex >= 0 ? triggerIndex : 0, galleryItems);
    } catch (_error) {
      window.open(trigger.getAttribute("href"), "_blank", "noopener,noreferrer");
    }
  });

  workspacePhotoLightboxBound = true;
  void setupPhotoLightbox().catch(() => {});
};

const bindDatePickerButtons = () => {
  if (document.body.dataset.workspaceDatePickerBound === "true") {
    return;
  }

  document.addEventListener("click", (event) => {
    const trigger = event.target.closest("[data-date-picker-button]");
    if (!trigger) return;

    const form = trigger.closest("form");
    const input = form?.querySelector("[data-date-picker-input]");
    if (!input) return;

    event.preventDefault();

    if (typeof input.showPicker === "function") {
      input.showPicker();
    } else {
      input.click();
    }
  });

  document.addEventListener("change", (event) => {
    const input = event.target.closest("[data-date-picker-input]");
    if (!input || !input.form) return;

    if (typeof input.form.requestSubmit === "function") {
      input.form.requestSubmit();
    } else {
      input.form.submit();
    }
  });

  document.body.dataset.workspaceDatePickerBound = "true";
};

const bindModalPortals = () => {
  if (workspaceModalPortalsBound) {
    return;
  }

  const hoistModal = (modal) => {
    if (!(modal instanceof HTMLElement)) return;
    if (modal.parentElement === document.body) return;

    document.body.appendChild(modal);
  };

  document.addEventListener("show.bs.modal", (event) => {
    const modal = event.target;
    if (!(modal instanceof HTMLElement) || !modal.classList.contains("modal")) {
      return;
    }

    hoistModal(modal);
  });

  workspaceModalPortalsBound = true;
};

const bindDropdownBackdrops = () => {
  if (workspaceDropdownBackdropsBound) {
    return;
  }

  document.addEventListener("shown.bs.dropdown", (event) => {
    const toggle = findBackdropDropdownToggle(event.relatedTarget) || findBackdropDropdownToggle(event.target);
    if (!(toggle instanceof HTMLElement)) {
      return;
    }

    const overlay = document.getElementById("overlay");
    setShellOverlayFlag(overlay, "dropdownActive", true);
  });

  document.addEventListener("hidden.bs.dropdown", (event) => {
    const toggle = findBackdropDropdownToggle(event.relatedTarget) || findBackdropDropdownToggle(event.target);
    if (!(toggle instanceof HTMLElement)) {
      return;
    }

    const overlay = document.getElementById("overlay");
    setShellOverlayFlag(overlay, "dropdownActive", hasBackdropDropdownOpen());
  });

  workspaceDropdownBackdropsBound = true;
};

const initializeWorkspace = () => {
  bindWorkspaceShell();
  bindCardLinks();
  bindPhotoLightbox();
  bindDatePickerButtons();
  bindModalPortals();
  bindDropdownBackdrops();
};

document.addEventListener("DOMContentLoaded", initializeWorkspace);
document.addEventListener("turbo:load", initializeWorkspace);
