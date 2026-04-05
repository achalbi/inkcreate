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
});
