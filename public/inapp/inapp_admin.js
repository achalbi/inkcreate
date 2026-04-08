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

const scheduleTimedMessages = () => {
  document.querySelectorAll("[data-auto-dismiss]").forEach((element) => {
    if (element.dataset.autoDismissBound === "true") {
      return;
    }

    element.dataset.autoDismissBound = "true";

    const delay = Number.parseInt(element.dataset.autoDismiss || "", 10);
    const timeout = Number.isFinite(delay) ? delay : 5000;

    window.setTimeout(() => {
      if (!element.isConnected || element.dataset.autoDismissState === "dismissing") {
        return;
      }

      element.dataset.autoDismissState = "dismissing";
      element.style.transition = "opacity 0.28s ease, transform 0.28s ease";
      element.style.opacity = "0";
      element.style.transform = "translateY(-8px) scale(0.98)";

      window.setTimeout(() => {
        if (element.isConnected) {
          element.remove();
        }
      }, 280);
    }, timeout);
  });
};

let adminModalPortalsBound = false;
let adminDropdownBackdropsBound = false;

const bindModalPortals = () => {
  if (adminModalPortalsBound) {
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

  adminModalPortalsBound = true;
};

const bindDropdownBackdrops = () => {
  if (adminDropdownBackdropsBound) {
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

  adminDropdownBackdropsBound = true;
};

document.addEventListener("DOMContentLoaded", () => {
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

  scheduleTimedMessages();
  bindModalPortals();
  bindDropdownBackdrops();
});
