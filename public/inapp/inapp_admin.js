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

document.addEventListener("DOMContentLoaded", () => {
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

  scheduleTimedMessages();
});
