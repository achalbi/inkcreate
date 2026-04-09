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
let workspaceIboxCollapsesBound = false;
let workspacePhotoRemovalConfirmBound = false;

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
        const thumbCropped = item.dataset.pswpCropped === "true" || item.dataset.cropped === "true";

        return {
          src: item.dataset.pswpSrc || item.getAttribute("href") || "",
          msrc: previewImage?.currentSrc || previewImage?.src || item.dataset.pswpSrc || item.getAttribute("href") || "",
          alt: item.dataset.photoLightboxAlt || previewImage?.alt || "Photo preview",
          width,
          height,
          thumbEl: previewImage || item,
          thumbCropped,
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
          showHideAnimationType: "zoom",
          pswpModule: () => import("/vendor/photoswipe/photoswipe.esm.js")
        });

        const setThumbnailTransitionState = (item, active) => {
          const thumbnail = item?.element?.closest(".thumbnail");
          if (!(thumbnail instanceof HTMLElement)) {
            return;
          }

          thumbnail.classList.toggle("is-pswp-transitioning", active);
        };

        lightbox.addFilter("thumbEl", (thumbEl, data) => data.thumbEl || data.element || thumbEl);
        lightbox.addFilter("placeholderSrc", (placeholderSrc, slide) => slide.data.msrc || placeholderSrc);
        lightbox.addFilter("itemData", (itemData, index) => {
          const element = itemData.element;
          if (!(element instanceof HTMLElement)) {
            return itemData;
          }

          return {
            ...itemData,
            thumbCropped: itemData.thumbCropped || element.dataset.pswpCropped === "true" || element.dataset.cropped === "true",
            downloadSrc: itemData.src,
            removePath: element.dataset.pswpRemovePath || "",
            removeMessage: element.dataset.pswpRemoveMessage || ""
          };
        });

        lightbox.on("openingAnimationStart", () => {
          setThumbnailTransitionState(lightbox.pswp?.currSlide?.data, true);
        });

        lightbox.on("closingAnimationStart", () => {
          setThumbnailTransitionState(lightbox.pswp?.currSlide?.data, true);
        });

        lightbox.on("openingAnimationEnd", () => {
          setThumbnailTransitionState(lightbox.pswp?.currSlide?.data, false);
        });

        lightbox.on("closingAnimationEnd", () => {
          setThumbnailTransitionState(lightbox.pswp?.currSlide?.data, false);
        });

        lightbox.on("uiRegister", () => {
          lightbox.pswp.ui.registerElement({
            name: "download-button",
            order: 7,
            isButton: true,
            tagName: "a",
            html: "<svg class='pswp__icn pswp__icn--download' viewBox='0 0 24 24' aria-hidden='true' fill='none' stroke='currentColor' stroke-width='1.9' stroke-linecap='round' stroke-linejoin='round'><path d='M12 4.5v9.5' /><path d='m8.75 10.75 3.25 3.25 3.25-3.25' /><path d='M5.5 18.5v1.25A1.75 1.75 0 0 0 7.25 21.5h9.5a1.75 1.75 0 0 0 1.75-1.75V18.5' /></svg>",
            onInit: (element, pswp) => {
              const updateDownloadLink = () => {
                const src = pswp.currSlide?.data?.downloadSrc || pswp.currSlide?.data?.src || "";
                element.setAttribute("href", src);
                element.setAttribute("download", "");
                element.hidden = src.length === 0;
              };

              element.setAttribute("aria-label", "Download photo");
              element.setAttribute("title", "Download photo");

              pswp.on("change", updateDownloadLink);
              updateDownloadLink();
            }
          });

          lightbox.pswp.ui.registerElement({
            name: "remove-photo-button",
            order: 8,
            isButton: true,
            tagName: "button",
            html: "<svg class='pswp__icn pswp__icn--remove' viewBox='0 0 24 24' aria-hidden='true' fill='none' stroke='currentColor' stroke-width='1.9' stroke-linecap='round' stroke-linejoin='round'><path d='M9 5.25h6' /><path d='M5.5 7.5h13' /><path d='M8 7.5v10.25A1.75 1.75 0 0 0 9.75 19.5h4.5A1.75 1.75 0 0 0 16 17.75V7.5' /><path d='M10.25 10.5v5.25' /><path d='M13.75 10.5v5.25' /></svg>",
            onInit: (element, pswp) => {
              const updateRemoveState = () => {
                const removePath = pswp.currSlide?.data?.removePath || "";
                element.hidden = removePath.length === 0;
              };

              element.setAttribute("type", "button");
              element.setAttribute("aria-label", "Remove photo");
              element.setAttribute("title", "Remove photo");

              element.addEventListener("click", () => {
                const removePath = pswp.currSlide?.data?.removePath || "";
                if (!removePath) {
                  return;
                }

                const removalDetail = {
                  path: removePath,
                  message: pswp.currSlide?.data?.removeMessage || "This photo will be removed."
                };

                let confirmQueued = false;
                const queueRemovalConfirm = () => {
                  if (confirmQueued) {
                    return;
                  }

                  confirmQueued = true;
                  document.dispatchEvent(new CustomEvent("workspace:photo-removal-confirm", {
                    detail: removalDetail
                  }));
                };

                pswp.on("destroy", queueRemovalConfirm);
                pswp.close();
              });

              pswp.on("change", updateRemoveState);
              updateRemoveState();
            }
          });

          lightbox.pswp.ui.registerElement({
            name: "custom-counter-bullets",
            className: "pswp__bullets-indicator",
            appendTo: "wrapper",
            onInit: (element, pswp) => {
              const updateBullets = () => {
                const totalSlides = pswp.getNumItems();
                element.innerHTML = "";
                element.hidden = totalSlides <= 1;

                for (let index = 0; index < totalSlides; index += 1) {
                  const bullet = document.createElement("span");
                  bullet.className = "pswp__bullet";
                  if (index === pswp.currIndex) {
                    bullet.classList.add("is-active");
                  }

                  element.appendChild(bullet);
                }
              };

              pswp.on("change", updateBullets);
              pswp.on("afterInit", updateBullets);
              updateBullets();
            }
          });

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

const bindPhotoRemovalConfirm = () => {
  const modalElement = document.getElementById("photoRemovalConfirmModal");
  const confirmButton = modalElement?.querySelector("[data-photo-removal-confirm-submit]");
  const messageElement = modalElement?.querySelector("[data-photo-removal-confirm-message]");
  const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || "";

  if (!(modalElement instanceof HTMLElement) || !(confirmButton instanceof HTMLElement) || !(messageElement instanceof HTMLElement)) {
    return;
  }

  const modal = window.bootstrap?.Modal.getOrCreateInstance(modalElement);
  if (!modal) {
    return;
  }

  const setPendingForm = (form) => {
    if (!(form instanceof HTMLFormElement)) {
      delete modalElement.dataset.pendingPhotoRemovalFormId;
      return;
    }

    if (!form.id) {
      form.id = `photo-removal-form-${Math.random().toString(36).slice(2, 10)}`;
    }

    modalElement.dataset.pendingPhotoRemovalFormId = form.id;
  };

  const getPendingForm = () => {
    const formId = modalElement.dataset.pendingPhotoRemovalFormId;
    if (!formId) {
      return null;
    }

    const form = document.getElementById(formId);
    return form instanceof HTMLFormElement ? form : null;
  };

  const setPendingPath = (path) => {
    if (typeof path !== "string" || path.length === 0) {
      delete modalElement.dataset.pendingPhotoRemovalPath;
      return;
    }

    modalElement.dataset.pendingPhotoRemovalPath = path;
  };

  const getPendingPath = () => modalElement.dataset.pendingPhotoRemovalPath || "";

  const openRemovalConfirm = ({ form = null, path = "", message = "" }) => {
    setPendingForm(form);
    setPendingPath(path);
    messageElement.textContent = message || "This photo will be removed.";
    modal.show();
  };

  document.querySelectorAll("form[data-photo-removal-confirm]").forEach((form) => {
    if (form instanceof HTMLFormElement && !form.id) {
      form.id = `photo-removal-form-${Math.random().toString(36).slice(2, 10)}`;
    }
  });

  if (workspacePhotoRemovalConfirmBound) {
    return;
  }

  document.addEventListener("workspace:photo-removal-confirm", (event) => {
    openRemovalConfirm({
      form: event.detail?.form || null,
      path: event.detail?.path || "",
      message: event.detail?.message || "This photo will be removed."
    });
  });

  document.addEventListener("submit", (event) => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement) || !form.matches("form[data-photo-removal-confirm]")) {
      return;
    }

    if (form.dataset.photoRemovalConfirmed === "true") {
      delete form.dataset.photoRemovalConfirmed;
      return;
    }

    event.preventDefault();
    openRemovalConfirm({
      form,
      message: form.dataset.photoRemovalConfirmMessage || "This photo will be removed."
    });
  });

  document.addEventListener("click", (event) => {
    const trigger = event.target.closest("[data-photo-removal-path]");
    if (!(trigger instanceof HTMLElement)) {
      return;
    }

    event.preventDefault();
    openRemovalConfirm({
      path: trigger.dataset.photoRemovalPath || "",
      message: trigger.dataset.photoRemovalMessage || "This photo will be removed."
    });
  });

  confirmButton.addEventListener("click", () => {
    const form = getPendingForm();
    const path = getPendingPath();

    if (form instanceof HTMLFormElement) {
      form.dataset.photoRemovalConfirmed = "true";
      modal.hide();

      if (typeof form.requestSubmit === "function") {
        form.requestSubmit();
      } else {
        form.submit();
      }

      return;
    }

    if (path) {
      const deleteForm = document.createElement("form");
      deleteForm.method = "post";
      deleteForm.action = path;
      deleteForm.hidden = true;

      if (csrfToken) {
        const csrfInput = document.createElement("input");
        csrfInput.type = "hidden";
        csrfInput.name = "authenticity_token";
        csrfInput.value = csrfToken;
        deleteForm.appendChild(csrfInput);
      }

      const methodInput = document.createElement("input");
      methodInput.type = "hidden";
      methodInput.name = "_method";
      methodInput.value = "delete";
      deleteForm.appendChild(methodInput);

      document.body.appendChild(deleteForm);
      modal.hide();
      deleteForm.submit();
      return;
    }

    modal.hide();
  });

  modalElement.addEventListener("hidden.bs.modal", () => {
    const form = getPendingForm();
    if (form instanceof HTMLFormElement) {
      delete form.dataset.photoRemovalConfirmed;
    }

    setPendingForm(null);
    setPendingPath("");
    messageElement.textContent = "This photo will be removed from the page.";
  });

  workspacePhotoRemovalConfirmBound = true;
};

const bindIboxCollapses = () => {
  const headerInteractiveSelector = "a, button, input, select, textarea, label, summary, [role='button'], [data-bs-toggle]";

  const ensureCollapseInner = (element) => {
    if (!(element instanceof HTMLElement) || !element.classList.contains("ibox-content")) {
      return;
    }

    if (element.dataset.iboxCollapsePrepared === "true") {
      return;
    }

    const existingInner = element.firstElementChild;
    if (existingInner instanceof HTMLElement && existingInner.classList.contains("ibox-content__inner") && element.children.length === 1) {
      element.dataset.iboxCollapsePrepared = "true";
      return;
    }

    const inner = document.createElement("div");
    inner.className = "ibox-content__inner";

    while (element.firstChild) {
      inner.appendChild(element.firstChild);
    }

    element.appendChild(inner);
    element.dataset.iboxCollapsePrepared = "true";
  };

  const getCollapseContext = (element) => {
    if (!(element instanceof HTMLElement) || !element.classList.contains("ibox-content") || !element.id) {
      return null;
    }

    const box = element.closest(".ibox");
    if (!(box instanceof HTMLElement)) {
      return null;
    }

    const targetSelector = `#${element.id}`;
    const toggles = Array.from(box.querySelectorAll(".ibox-toggle-button")).filter((toggle) => {
      if (!(toggle instanceof HTMLElement)) {
        return false;
      }

      const selector = toggle.getAttribute("data-bs-target") || toggle.getAttribute("href");
      return selector === targetSelector;
    });

    if (toggles.length === 0) {
      return null;
    }

    return { box, toggles };
  };

  const syncToggleMetadata = (toggle, expanded) => {
    if (!(toggle instanceof HTMLElement)) {
      return;
    }

    toggle.setAttribute("aria-expanded", expanded ? "true" : "false");
    toggle.setAttribute("title", expanded ? "Collapse section" : "Expand section");
  };

  const resolveCollapseElement = (box, toggle) => {
    if (!(box instanceof HTMLElement) || !(toggle instanceof HTMLElement)) {
      return null;
    }

    const selector = toggle.getAttribute("data-bs-target") || toggle.getAttribute("href");
    if (!selector) {
      return null;
    }

    const collapseElement = box.querySelector(selector) || document.querySelector(selector);
    return collapseElement instanceof HTMLElement && collapseElement.classList.contains("ibox-content") ? collapseElement : null;
  };

  const getCollapseFromTitle = (title) => {
    if (!(title instanceof HTMLElement) || !title.classList.contains("ibox-title")) {
      return null;
    }

    const box = title.closest(".ibox");
    if (!(box instanceof HTMLElement)) {
      return null;
    }

    const toggles = Array.from(title.querySelectorAll(".ibox-toggle-button"));
    for (const toggle of toggles) {
      if (!(toggle instanceof HTMLElement)) {
        continue;
      }

      const collapseElement = resolveCollapseElement(box, toggle);
      if (collapseElement instanceof HTMLElement) {
        return collapseElement;
      }
    }

    return null;
  };

  const getCollapseToggleFromTitle = (title) => {
    if (!(title instanceof HTMLElement) || !title.classList.contains("ibox-title")) {
      return null;
    }

    const box = title.closest(".ibox");
    if (!(box instanceof HTMLElement)) {
      return null;
    }

    const toggles = Array.from(title.querySelectorAll(".ibox-toggle-button[data-bs-toggle='collapse']"));
    for (const toggle of toggles) {
      if (!(toggle instanceof HTMLElement)) {
        continue;
      }

      const collapseElement = resolveCollapseElement(box, toggle);
      if (collapseElement instanceof HTMLElement) {
        return { toggle, collapseElement };
      }
    }

    return null;
  };

  const setCollapseState = (element, state) => {
    ensureCollapseInner(element);

    const context = getCollapseContext(element);
    if (!context) {
      return;
    }

    const { box, toggles } = context;
    const expanded = state === "expanded" || state === "expanding";

    box.dataset.iboxCollapsible = "true";
    box.classList.remove("is-expanded", "is-collapsed", "is-expanding", "is-collapsing");
    box.classList.add(`is-${state}`);

    toggles.forEach((toggle) => syncToggleMetadata(toggle, expanded));
  };

  document.querySelectorAll(".ibox-content.collapse").forEach((element) => {
    ensureCollapseInner(element);
    setCollapseState(element, element.classList.contains("show") ? "expanded" : "collapsed");
  });

  if (workspaceIboxCollapsesBound) {
    return;
  }

  document.addEventListener("show.bs.collapse", (event) => {
    setCollapseState(event.target, "expanding");
  });

  document.addEventListener("shown.bs.collapse", (event) => {
    setCollapseState(event.target, "expanded");
  });

  document.addEventListener("hide.bs.collapse", (event) => {
    setCollapseState(event.target, "collapsing");
  });

  document.addEventListener("hidden.bs.collapse", (event) => {
    setCollapseState(event.target, "collapsed");
  });

  document.addEventListener("click", (event) => {
    if (event.defaultPrevented) {
      return;
    }

    const title = event.target.closest(".ibox-title");
    if (!(title instanceof HTMLElement)) {
      return;
    }

    const collapseTarget = getCollapseToggleFromTitle(title);
    if (!collapseTarget) {
      return;
    }

    if (event.target.closest(".ibox-toggle-button[data-bs-toggle='collapse']")) {
      return;
    }

    if (event.target.closest(headerInteractiveSelector)) {
      return;
    }

    if (window.getSelection && window.getSelection().toString()) {
      return;
    }

    const collapse = window.bootstrap?.Collapse.getOrCreateInstance(collapseTarget.collapseElement, { toggle: false });
    collapse?.toggle();
  });

  workspaceIboxCollapsesBound = true;
};

const initializeWorkspace = () => {
  bindWorkspaceShell();
  bindCardLinks();
  bindPhotoLightbox();
  bindDatePickerButtons();
  bindModalPortals();
  bindDropdownBackdrops();
  bindPhotoRemovalConfirm();
  bindIboxCollapses();
};

document.addEventListener("DOMContentLoaded", initializeWorkspace);
document.addEventListener("turbo:load", initializeWorkspace);
