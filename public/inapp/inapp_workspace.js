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
      if (overlay) overlay.classList.add("show");
    });
  }

  if (overlay) {
    overlay.addEventListener("click", () => {
      if (sidebar) sidebar.classList.remove("mobile-show");
      overlay.classList.remove("show");
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

const bindPhotoLightbox = () => {
  if (document.body.dataset.workspacePhotoLightboxBound === "true") {
    return;
  }

  const modalElement = document.getElementById("photoLightboxModal");
  const modalImage = document.getElementById("photoLightboxImage");
  const modalCounter = document.getElementById("photoLightboxCounter");
  const modalCaption = document.getElementById("photoLightboxCaption");
  const previousButton = document.getElementById("photoLightboxPrev");
  const nextButton = document.getElementById("photoLightboxNext");

  if (!modalElement || !modalImage || !modalCounter || !modalCaption || !previousButton || !nextButton || typeof bootstrap === "undefined") {
    return;
  }

  const lightbox = bootstrap.Modal.getOrCreateInstance(modalElement);
  let galleryItems = [];
  let activeIndex = 0;

  const collectGalleryItems = (trigger) => {
    const galleryGroup = trigger.dataset.photoLightboxGroup || "workspace-gallery";

    return Array.from(document.querySelectorAll(`[data-photo-lightbox-group="${galleryGroup}"][data-photo-lightbox-src]`));
  };

  const renderLightboxImage = (index) => {
    const currentTrigger = galleryItems[index];
    if (!currentTrigger) return;

    activeIndex = index;
    modalImage.src = currentTrigger.dataset.photoLightboxSrc || "";
    modalImage.alt = currentTrigger.dataset.photoLightboxAlt || "Photo preview";
    modalCounter.textContent = `${index + 1} / ${galleryItems.length}`;
    modalCaption.textContent = currentTrigger.dataset.photoLightboxAlt || "Photo preview";

    const singleImage = galleryItems.length <= 1;
    previousButton.disabled = singleImage;
    nextButton.disabled = singleImage;
    previousButton.hidden = singleImage;
    nextButton.hidden = singleImage;
  };

  const moveLightbox = (direction) => {
    if (galleryItems.length <= 1) return;

    const nextIndex = (activeIndex + direction + galleryItems.length) % galleryItems.length;
    renderLightboxImage(nextIndex);
  };

  document.addEventListener("click", (event) => {
    const trigger = event.target.closest("[data-photo-lightbox-src]");
    if (!trigger) return;

    event.preventDefault();

    galleryItems = collectGalleryItems(trigger);
    const triggerIndex = galleryItems.indexOf(trigger);
    renderLightboxImage(triggerIndex >= 0 ? triggerIndex : 0);
    lightbox.show();
  });

  previousButton.addEventListener("click", () => moveLightbox(-1));
  nextButton.addEventListener("click", () => moveLightbox(1));

  document.addEventListener("keydown", (event) => {
    if (!modalElement.classList.contains("show")) return;

    if (event.key === "ArrowLeft") {
      event.preventDefault();
      moveLightbox(-1);
    }

    if (event.key === "ArrowRight") {
      event.preventDefault();
      moveLightbox(1);
    }
  });

  modalElement.addEventListener("shown.bs.modal", () => {
    const backdrops = document.querySelectorAll(".modal-backdrop");
    const latestBackdrop = backdrops[backdrops.length - 1];
    if (latestBackdrop) latestBackdrop.classList.add("photo-lightbox-backdrop");
  });

  modalElement.addEventListener("hidden.bs.modal", () => {
    modalImage.removeAttribute("src");
    modalImage.removeAttribute("alt");
    modalCounter.textContent = "";
    modalCaption.textContent = "";
    galleryItems = [];
    activeIndex = 0;
  });

  document.body.dataset.workspacePhotoLightboxBound = "true";
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

const initializeWorkspace = () => {
  bindWorkspaceShell();
  bindCardLinks();
  bindPhotoLightbox();
  bindDatePickerButtons();
};

document.addEventListener("DOMContentLoaded", initializeWorkspace);
document.addEventListener("turbo:load", initializeWorkspace);
